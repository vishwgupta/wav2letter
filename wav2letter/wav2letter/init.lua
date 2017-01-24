local tnt = require 'torchnet'

require 'torch'
require 'nn'

require 'wav2letter.viterbi'
require 'wav2letter.fullconnectcriterion'
require 'wav2letter.fullconnectcriterionc'
require 'wav2letter.connectionisttemporalcriterion'
require 'wav2letter.linearsegcriterion'
require 'wav2letter.multistatefullconnectcriterion'
require 'wav2letter.forcealigncriterion'
require 'wav2letter.forcealigncriterionc'
require 'wav2letter.crossentropyforcealigncriterion'
require 'wav2letter.autosegcriterion'
require 'wav2letter.fullconnectgarbagecriterion'
require 'wav2letter.forcealigngarbagecriterion'

require 'wav2letter.editdistancemeter'
require 'wav2letter.frameerrormeter'
require 'wav2letter.speechstatmeter'

require 'wav2letter.zeronet'
require 'wav2letter.shiftnet'
require 'wav2letter.dataparalleltabletable'

require 'wav2letter.shiftdataset'
require 'wav2letter.batchcriterion'
require 'wav2letter.batchautosegcriterionc'
require 'wav2letter.multithreadedbatchcriterion'

return tnt