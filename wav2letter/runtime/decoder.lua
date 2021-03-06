-- Copyright (c) 2017-present, Facebook, Inc.
-- All rights reserved.

-- This source code is licensed under the BSD-style license found in the
-- LICENSE file in the root directory of this source tree. An additional grant
-- of patent rights can be found in the PATENTS file in the same directory.

local beamer = require 'beamer'
local tds = require 'tds'

local LMUNK = "<unk>"

local function loadwordhash(filename, maxn)
   print(string.format('[loading %s]', filename))
   local hash = tds.Hash()
   local i = 0 -- 0 based
   for line in io.lines(filename) do
      local word, spelling = line:match('^(%S+)%s+(%S+)$')
      assert(word and spelling, string.format("error parsing <%s> at line #%d", filename, i+1))
      if not hash[word] then
         hash[word] = tds.Hash{idx=i, word=word, spellings=tds.Vec{}}
         hash[i] = hash[word]
         i = i + 1
      end
      hash[word].spellings[#hash[word].spellings+1] = spelling
      if maxn and maxn > 0 and maxn == i then
         break
      end
   end
   print(string.format('[%d tokens found]', i))
   return hash
end

local function loadletterhash(filename, maxn)
   print(string.format('[loading %s]', filename))
   local hash = {}
   local i = 0 -- 0 based
   for letter in io.lines(filename) do
      letter = letter:match('([^\n]+)') or letter
      hash[letter] = i
      hash[i] = letter
      i = i + 1
   end
   print(string.format('[%d letters found]', i))
   return hash
end


-- config and opt options?
local function decoder(letterdictname, worddictname, lmname, smearing, nword)
   local words = loadwordhash(worddictname, nword)
   local letters = loadletterhash(letterdictname)

   -- add <unk> in words (only :))
   if not words[LMUNK] then
      local def = tds.Hash{idx=#words/2, word=LMUNK, spellings=tds.Vec{}}
      words[def.idx] = def
      words[def.word] = def
   end

   local buffer = torch.LongTensor()
   local function spelling2tensor(word)
      buffer:resize(#word)
      for i=1,#word do
         if not letters[word:sub(i, i)] then
            error(string.format('unknown letter <%s>', word:sub(i, i)))
         end
         buffer[i] = letters[word:sub(i, i)]
      end
      return buffer
   end

   local lm = beamer.LM(lmname)
   local sil = letters['|']
   local unk = {lm=lm:index(LMUNK), usr=words[LMUNK].idx}

   local trie = beamer.Trie(#letters+1, sil) -- 0 based
   for i=0,#words/2-1 do
      local lmidx = lm:index(words[i].word)
      words[i].lmidx = lmidx
      local _, score = lm:score(lmidx)
      assert(score < 0)
      for _, spelling in ipairs(words[i].spellings) do
         trie:insert(spelling2tensor(spelling), {lm=lmidx, usr=i}, score)
      end
   end

   local function toword(usridx)
      local word = words[usridx]
      assert(word, 'unknown word index')
      return word.word
   end

   if smearing == 'max' then
      trie:smearing()
   elseif smearing == 'logadd' then
      trie:smearing(true)
   elseif smearing ~= 'none' then
      error('smearing should be none, max or logadd')
   end

   print(string.format('[Lexicon Trie memory usage: %.2f Mb]', trie:mem()/2^20))
   local decoder = beamer.Decoder(trie, lm, sil, unk)
   decoder:settoword(toword)
   local scores = torch.FloatTensor()
   local labels = torch.LongTensor()
   local llabels = torch.LongTensor()

   local function decode(opt, transitions, emissions, K)
      K = K or 1
      decoder:decode(opt, transitions, emissions, scores, llabels, labels)
      local function bestpath(k)
         local sentence = {}
         local lsentence = {}
         if labels:nDimension() > 0 then
            local labels = labels[k]
            local llabels = llabels[k]
            for j=1,labels:size(1) do
               local letteridx = llabels[j]
               local wordidx = labels[j]
               if letteridx >= 0 then
                  assert(letters[letteridx])
                  table.insert(lsentence, letteridx)
               end
               if wordidx >= 0 then
                  assert(words[wordidx])
                  table.insert(sentence, wordidx)
               end
            end
         end
         return torch.LongTensor(sentence), torch.LongTensor(lsentence), scores[k]
      end
      if K == 1 then
         return bestpath(1)
      else
         local sentences = {}
         local lsentences = {}
         local scores = {}
         if labels:nDimension() > 0 then
            for k=1,math.min(K, labels:size(1)) do
               local sentence, lsentence, score = bestpath(k)
               table.insert(sentences, sentence)
               table.insert(lsentences, lsentence)
               table.insert(scores, score)
            end
         end
         return sentences, lsentences, scores
      end
   end

   local function lettertensor2string(t)
      local str = {}
      for i=1,t:size(1) do
         table.insert(str, assert(letters[t[i]]))
      end
      return table.concat(str)
   end

   local function tensor2string(t)
      if t:nDimension() == 0 then
         return ""
      end
      local str = {}
      for i=1,t:size(1) do
         table.insert(str, toword(t[i]))
      end
      return table.concat(str, ' ')
   end

   local function string2tensor(str, funk)
      local t = {}
      for word in str:gmatch('(%S+)') do
         local idx
         if words[word] then
            idx = words[word].idx
         else
            if funk then
               funk(word)
            end
            idx = words[LMUNK].idx
         end
         table.insert(t, idx)
      end
      return torch.LongTensor(t)
   end

   local function removeunk(t)
      return t:maskedSelect(t:ne(unk.usr))
   end

   local function removeneg(t)
      return t:maskedSelect(t:ge(0))
   end

   local function usridx2lmidx(t)
      local lmt = t.new():resizeAs(t)
      for i=1,t:size(1) do
         lmt[i] = words[t[i]].lmidx
      end
      return lmt
   end

   local obj = {
      words = words,
      letters = letters,
      lm = lm,
      trie = trie,
      sil = sil,
      decoder = decoder,
      decode = decode,
      toword = toword, -- usridx to word
      spelling2tensor = spelling2tensor, -- word to letter idx
      string2tensor = string2tensor, -- string to usr word indices
      tensor2string = tensor2string, -- usr word indices to string
      lettertensor2string = lettertensor2string, -- letter indices to string
      removeunk = removeunk,
      removeneg = removeneg,
      usridx2lmidx = usridx2lmidx
   }
   setmetatable(obj, {__call=function(...) return decode(select(2, ...), select(3, ...)) end})

   return obj
end

return decoder
