#!/usr/bin/env bash
#
# Copyright (c) 2021 Intel Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

MODEL_DIR=${MODEL_DIR-$PWD}

if [ -z "${OUTPUT_DIR}" ]; then
  echo "The required environment variable OUTPUT_DIR has not been set"
  exit 1
fi

# Create the output directory in case it doesn't already exist
mkdir -p ${OUTPUT_DIR}

if [ -z "${DATASET_DIR}" ]; then
  echo "The required environment variable DATASET_DIR has not been set"
  exit 1
fi

if [ ! -d "${DATASET_DIR}" ]; then
  echo "The DATASET_DIR '${DATASET_DIR}' does not exist"
  exit 1
fi

if [ -z "${PRECISION}" ]; then
  echo "The required environment variable PRECISION has not been set"
  echo "Please set PRECISION to fp32, bfloat32 or bfloat16."
  exit 1
elif [ ${PRECISION} != "fp32" ] && [ ${PRECISION} != "bfloat16" ] && [ ${PRECISION} != "bfloat32" ]; then
  echo "The specified precision '${PRECISION}' is unsupported."
  echo "Supported precisions are: fp32, bfloat32 and bfloat16"
  exit 1
fi

# Get number of cores per socket line from lscpu
cores_per_socket=$(lscpu |grep 'Core(s) per socket:' |sed 's/[^0-9]//g')
cores_per_socket="${cores_per_socket//[[:blank:]]/}"

# Select the num_intra_threads
if [ ${PRECISION} == "fp32" ] || [ ${PRECISION} == "bfloat32" ]; then
  num_intra_threads=$(($cores_per_socket - 4))
elif [ ${PRECISION} == "bfloat16" ]; then
  export KMP_BLOCKTIME=5
  num_intra_threads=$(($cores_per_socket - 2))
fi

NUM_INSTANCES="1"

# If batch size env is not mentioned, then the workload will run with the default batch size.
if [ -z "${BATCH_SIZE}"]; then
  if [ ${PRECISION} == "fp32" ] || [ ${PRECISION} == "bfloat32" ]; then
    BATCH_SIZE="5200"
    echo "Running with default batch size of ${BATCH_SIZE}"
  elif [ ${PRECISION} == "bfloat16" ]; then
    BATCH_SIZE="12000"
    echo "Running with default batch size of ${BATCH_SIZE}"
  fi
fi

# Set up env variable for bfloat32
if [[ $PRECISION == "bfloat32" ]]; then
  ONEDNN_DEFAULT_FPMATH_MODE=BF16
  PRECISION="fp32"
fi

export TF_PATTERN_ALLOW_CTRL_DEPENDENCIES=1

source "${MODEL_DIR}/quickstart/common/utils.sh"
_ht_status_spr
_command python ${MODEL_DIR}/benchmarks/launch_benchmark.py \
  --model-name=transformer_mlperf \
  --precision=${PRECISION} \
  --mode=training \
  --framework tensorflow \
  --data-location=${DATASET_DIR} \
  --output-dir ${OUTPUT_DIR} \
  --mpi_num_processes=${NUM_INSTANCES} \
  --mpi_num_processes_per_socket=1 \
  --batch-size ${BATCH_SIZE} \
  --num-intra-threads ${num_intra_threads} \
  --num-inter-threads 2 \
  $@ \
  -- random_seed=11 train_steps=100 \
  steps_between_eval=100 params=big \
  save_checkpoints='No' do_eval='No' print_iter=10 2>&1 | tee ${OUTPUT_DIR}/transformer_mlperf${PRECISION}_training_bs${BATCH_SIZE}_all_instances.log

if [[ $? == 0 ]]; then
  cat ${OUTPUT_DIR}/transformer_mlperf${PRECISION}_training_bs${BATCH_SIZE}_all_instances.log | grep "INFO:tensorflow:Batch" | tail -n 2 | sed -e "s/.* = //"
  exit 0
else
  exit 1
fi

