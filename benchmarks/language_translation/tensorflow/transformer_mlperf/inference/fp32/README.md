<!--- 0. Title -->
# Transformer Language FP32 Inference

<!-- 10. Description -->
## Description

This document has instructions for running Transformer Language FP32 Inference in mlperf
Benchmark suits using Intel-optimized TensorFlow.

Detailed information on mlperf Benchmark can be found in [mlcommons/training](https://github.com/mlcommons/training/tree/v0.5/translation/tensorflow/transformer)

The inference code is based on the trasnformer mlperf evaluation code, but Intel has optimized the inference model by modifying the code of the model, so that it can achieve better performance on Intel CPUs.

<!--- 30. Datasets -->
## Datasets

Follow [instructions](https://github.com/IntelAI/models/tree/master/datasets/transformer_data/README.md) to download and preprocess the WMT English-German dataset.
Set `DATA_DIR` to point out to the location of the dataset directory.

Download the pretrained model using the browser or if you run on Linux, run:
```
wget https://storage.googleapis.com/intel-optimized-tensorflow/models/2_10_0/transformer_mlperf_fp32.pb
```
Set the `PB_FILE` environment variable to local file path on your system.

The translate can be run with accuracy mode or benchmark mode. The benchmark mode will run with the best performance by setting warmup steps and the total steps users want to run. The accuracy mode will just run for testing accuracy without setting warmup steps and steps.

## Run the model on Linux
Set the environment variables to point to the dataset directory `DATA_DIR`, the pretrained model path `PB_FILE`, batch size `BATCH_SIZE`, the number of sockets `NUM_SOCKETS`, and the number of cores on your system `NUM_CORES`.
```
export PB_FILE=<path to the frozen pre trained model file>
export DATA_DIR=<the input data directory, which should include newstest2014.en, newstest2014.de and vocab.ende.32768>
export BATCH_SIZE=1
export NUM_SOCKETS=2
```
#### Benchmark mode:
```
  python3 ./benchmarks/launch_benchmark.py    \
     --benchmark-only --framework tensorflow  \
     --in-graph=$PB_FILE \
     --model-name transformer_mlperf \
     --mode inference --precision fp32 \
     --batch-size $BATCH_SIZE \
     --num-intra-threads $NUM_CORES --num-inter-threads $NUM_SOCKETS \
     --verbose \
     --data-location $DATA_DIR \
     --docker-image intel/intel-optimized-tensorflow:latest \
     -- params=big \
        file=newstest2014.en \
        vocab_file=vocab.ende.32768 \
        file_out=translation.en \
        reference=newstest2014.de \
        warmup_steps=3 \
        steps=100 
```
#### Accuracy mode:
```
  python3 ./benchmarks/launch_benchmark.py    \
     --accuracy-only --framework tensorflow  \
     --in-graph=$PB_FILE \
     --model-name transformer_mlperf \
     --mode inference --precision fp32 \
     --batch-size $BATCH_SIZE \
     --num-intra-threads $NUM_CORES --num-inter-threads $NUM_SOCKETS \
     --verbose \
     --data-location $DATA_DIR \
     --docker-image intel/intel-optimized-tensorflow:latest \
     -- params=big \
        file=newstest2014.en \
        vocab_file=vocab.ende.32768 \
        file_out=translation.en \
        reference=newstest2014.de \
        steps=100 
```
where:

   * $DATA_DIR -- the input data directory, which should include newstest2014.en, newstest2014.de and vocab.ende.32768
   * $PB_FILE  -- the path of the frozen model generated with the script, or downloaded from Intel published trained models websites
   * steps -- the number of batches of data to feed into the model for inference, if the number is greater than available batches in the input data, it will only run number of batches available in the data.

The log file is saved to the value of --output-dir. if not value spacified, the log will be at the models/benchmarks/common/tensorflow/logs in workspace.
With accuracy mode, the official BLEU score will be printed

The performance and accuracy in the the log output when the benchmarking completes should look
something like this, the real throughput and inferencing time varies:
```
  Total inferencing time: xxx
  Throughput: xxx  sentences/second
  Case-insensitive results: 26.694846153259277
  Case-sensitive results: 26.182371377944946
```

## Run the model on Windows
If not already setup, please follow instructions for [environment setup on Windows](/docs/general/Windows.md).

Set the environment variables to point to the dataset directory `DATA_DIR`, the path to the pretrained model file `PB_FILE`, batch size `BATCH_SIZE`, and  the number of sockets `NUM_SOCKETS`.
You can use `wmic cpu get SocketDesignation` to list the available socket on your system, then set `NUM_SOCKETS` accordingly.
```
set PB_FILE=<path to the directory where the frozen pre trained model file saved>\\transformer_mlperf_fp32.pb
set DATA_DIR=<the input data directory, which should include newstest2014.en, newstest2014.de and vocab.ende.32768>
set BATCH_SIZE=1
set NUM_SOCKETS=2
```
#### Benchmark mode:
Using `cmd.exe`, run:
```
  cd benchmarks
  python launch_benchmark.py    ^
     --benchmark-only --framework tensorflow  ^
     --in-graph=%PB_FILE% ^
     --model-name transformer_mlperf ^
     --mode inference --precision fp32 ^
     --batch-size %BATCH_SIZE% ^
     --num-intra-threads %NUMBER_OF_PROCESSORS% --num-inter-threads %NUM_SOCKETS% ^
     --verbose ^
     --data-location %DATA_DIR% ^
     -- params=big ^
        file=newstest2014.en ^
        vocab_file=vocab.ende.32768 ^
        file_out=translation.en ^
        reference=newstest2014.de ^
        warmup_steps=3 ^
        steps=100 
```
#### Accuracy mode:
Using `cmd.exe`, run:
```
  cd benchmarks
  python launch_benchmark.py    ^
     --accuracy-only --framework tensorflow  ^
     --in-graph=%PB_FILE% ^
     --model-name transformer_mlperf ^
     --mode inference --precision fp32 ^
     --batch-size %BATCH_SIZE% ^
     --num-intra-threads %NUMBER_OF_PROCESSORS% --num-inter-threads %NUM_SOCKETS% ^
     --verbose ^
     --data-location %DATA_DIR% ^
     -- params=big ^
        file=newstest2014.en ^
        vocab_file=vocab.ende.32768 ^
        file_out=translation.en ^
        reference=newstest2014.de ^
        steps=100 
```
where:
   * steps -- the number of batches of data to feed into the model for inference, if the number is greater than available batches in the input data, it will only run number of batches available in the data.
  