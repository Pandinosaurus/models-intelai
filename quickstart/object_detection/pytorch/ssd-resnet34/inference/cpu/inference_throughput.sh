#!/usr/bin/env bash
#
# Copyright (c) 2020 Intel Corporation
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

if [ ! -e "${MODEL_DIR}/models/object_detection/pytorch/ssd-resnet34/inference/cpu/infer.py" ]; then
  echo "Could not find the script of infer.py. Please set environment variable '\${MODEL_DIR}'."
  echo "From which the infer.py exist at the: \${MODEL_DIR}/models/object_detection/pytorch/ssd-resnet34/inference/cpu/infer.py"
  exit 1
fi

if [ ! -e "${CHECKPOINT_DIR}/pretrained/resnet34-ssd1200.pth" ]; then
  echo "The pretrained model \${CHECKPOINT_DIR}/pretrained/resnet34-ssd1200.pth does not exist"
  exit 1
fi

if [ ! -d "${DATASET_DIR}/coco" ]; then
  echo "The DATASET_DIR \${DATASET_DIR}/coco does not exist"
  exit 1
fi

if [ ! -d "${OUTPUT_DIR}" ]; then
  echo "The OUTPUT_DIR '${OUTPUT_DIR}' does not exist"
  exit 1
fi

if [[ "$1" == *"avx"* ]]; then
    unset DNNL_MAX_CPU_ISA
fi

ARGS=""
if [[ "$1" == "int8" || "$1" == "avx-int8" ]]; then
    ARGS="$ARGS --int8"
    ARGS="$ARGS --seed 1 --threshold 0.2 --configure ${MODEL_DIR}/models/object_detection/pytorch/ssd-resnet34/inference/cpu/pytorch_default_recipe_ssd_configure.json"
    export DNNL_GRAPH_CONSTANT_CACHE=1
    echo "### running int8 datatype"
elif [[ "$1" == "bf16" ]]; then
    ARGS="$ARGS --autocast"
    echo "### running bf16 datatype"
elif [[ "$1" == "fp32" || "$1" == "avx-fp32" ]]; then
    echo "### running fp32 datatype"
elif [[ "$1" == "bf32" ]]; then
    ARGS="$ARGS --bf32"
    echo "### running bf32 datatype"
else
    echo "The specified precision '$1' is unsupported."
    echo "Supported precisions are: fp32, avx-fp32, bf16, int8, bf32, and avx-int8"
    exit 1
fi

export DNNL_PRIMITIVE_CACHE_CAPACITY=1024
export USE_IPEX=1
export KMP_BLOCKTIME=1
export KMP_AFFINITY=granularity=fine,compact,1,0

rm -rf ${OUTPUT_DIR}/throughput_log*

PRECISION=$1
weight_sharing=true
if [ -z "${WEIGHT_SHAREING}" ]; then
  weight_sharing=false
else
  echo "### Running the test with runtime extension."
  weight_sharing=true
fi

if [ "$weight_sharing" = true ]; then
    async=true
    if [ "$async" = true ]; then
       ARGS="$ARGS --async-execution"
    fi
    CORES=`lscpu | grep Core | awk '{print $4}'`
    SOCKETS=`lscpu | grep Socket | awk '{print $2}'`
    TOTAL_CORES=`expr $CORES \* $SOCKETS`
    CORES_PER_INSTANCE=$CORES
    INSTANCES=`expr $TOTAL_CORES / $CORES_PER_INSTANCE`
    LAST_INSTANCE=`expr $INSTANCES - 1`
    INSTANCES_PER_SOCKET=`expr $INSTANCES / $SOCKETS`

    BATCH_PER_STREAM=2
    CORES_PER_STREAM=1
    STREAM_PER_INSTANCE=`expr $CORES / $CORES_PER_STREAM`
    BATCH_SIZE=`expr $BATCH_PER_STREAM \* $STREAM_PER_INSTANCE`

    export OMP_NUM_THREADS=$CORES_PER_STREAM

    for i in $(seq 0 $LAST_INSTANCE); do
        numa_node_i=`expr $i / $INSTANCES_PER_SOCKET`
        start_core_i=`expr $i \* $CORES_PER_INSTANCE`
        end_core_i=`expr $start_core_i + $CORES_PER_INSTANCE - 1`
        LOG_i=throughput_log_weight_sharing_${i}.log

        echo "### running on instance $i, numa node $numa_node_i, core list {$start_core_i, $end_core_i}..."
        numactl --physcpubind=$start_core_i-$end_core_i --membind=$numa_node_i python -u \
            ${MODEL_DIR}/models/object_detection/pytorch/ssd-resnet34/inference/cpu/infer_weight_sharing.py \
            --data ${DATASET_DIR}/coco \
            --device 0 \
            --checkpoint ${CHECKPOINT_DIR}/pretrained/resnet34-ssd1200.pth \
            -w 10 \
            -j 0 \
            --no-cuda \
            --iteration 50 \
            --batch-size ${BATCH_SIZE} \
            --jit \
            --number-instance $STREAM_PER_INSTANCE \
            --use-multi-stream-module \
            --instance-number $i \
            $ARGS 2>&1 | tee ${OUTPUT_DIR}/$LOG_i &
    done
    wait

else
    BATCH_SIZE=112
    python -m intel_extension_for_pytorch.cpu.launch \
        --use_default_allocator \
        --throughput_mode \
        ${MODEL_DIR}/models/object_detection/pytorch/ssd-resnet34/inference/cpu/infer.py \
        --data ${DATASET_DIR}/coco \
        --device 0 \
        --checkpoint ${CHECKPOINT_DIR}/pretrained/resnet34-ssd1200.pth \
        -w 10 \
        -j 0 \
        --no-cuda \
        --iteration 50 \
        --batch-size ${BATCH_SIZE} \
        --jit \
        --throughput-mode \
        $ARGS 2>&1 | tee ${OUTPUT_DIR}/throughput_log_ssdresnet34_${PRECISION}.log

    # For the summary of results
    wait
fi
throughput=$(grep 'Throughput:' ${OUTPUT_DIR}/throughput_log* |sed -e 's/.*Throughput//;s/[^0-9.]//g' |awk '
BEGIN {
        sum = 0;
i = 0;
      }
      {
        sum = sum + $1;
i++;
      }
END   {
sum = sum / i;
        printf("%.3f", sum);
}')
echo ""SSD-RN34";"throughput";$1; ${BATCH_SIZE};${throughput}" | tee -a ${OUTPUT_DIR}/summary.log
