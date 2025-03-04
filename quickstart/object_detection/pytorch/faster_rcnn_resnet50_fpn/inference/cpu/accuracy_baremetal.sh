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

if [ ! -e "${MODEL_DIR}/models/object_detection/pytorch/faster_rcnn_resnet50_fpn/inference/cpu/inference.py" ]; then
  echo "Could not find the script of infer.py. Please set environment variable '\${MODEL_DIR}'."
  echo "From which the infer.py exist at the: \${MODEL_DIR}/models/object_detection/pytorch/faster_rcnn_resnet50_fpn/inference/cpu/inference.py"
  exit 1
fi

if [ ! -d "${DATASET_DIR}/coco" ]; then
  echo "The DATASET_DIR \${DATASET_DIR}/coco does not exist"
  exit 1
fi

if [ -z "${OUTPUT_DIR}" ]; then
  echo "The required environment variable OUTPUT_DIR has not been set"
  exit 1
fi

# Create the output directory in case it doesn't already exist
mkdir -p ${OUTPUT_DIR}

ARGS=""
IPEX_ARGS=""
PRECISION="fp32"
if [ "$1" == "bf16" ]; then
  ARGS="$ARGS --precision bf16"
  PRECISION="bf16"
  echo "### running bf16 datatype"
elif [ "$1" == "fp32" ]; then
  ARGS="$ARGS --precision fp32"
  echo "### running fp32 datatype"
else
  echo "The specified precision '$1' is unsupported."
  echo "Supported precisions are: fp32 and bf16"
  exit 1
fi

export DNNL_PRIMITIVE_CACHE_CAPACITY=1024
export USE_IPEX=1
export KMP_BLOCKTIME=1
export KMP_AFFINITY=granularity=fine,compact,1,0

source "${MODEL_DIR}/quickstart/common/utils.sh"
_get_platform_type

if [[ ${PLATFORM} == "windows" ]]; then
  CORES="${NUMBER_OF_PROCESSORS}"
else
  CORES=`lscpu | grep Core | awk '{print $4}'`
fi
BATCH_SIZE=`expr $CORES \* 2`

rm -rf ${OUTPUT_DIR}/fasterrcnn_resnet50_fpn_accuracy_log_${PRECISION}_*

# check if stoch PYT or IPEX is installed on the system
pip list | grep intel-extension-for-pytorch
if [[ "$?" == 0 ]]; then
  IPEX_ARGS="-m intel_extension_for_pytorch.cpu.launch --use_default_allocator \
  --log_path=${OUTPUT_DIR} \
  --log_file_prefix="fasterrcnn_resnet50_fpn_accuracy_log_${PRECISION}""
  ARGS="$ARGS --ipex "
fi
python ${IPEX_ARGS} \
  ${MODEL_DIR}/models/object_detection/pytorch/faster_rcnn_resnet50_fpn/inference/cpu/inference.py \
  --data_path ${DATASET_DIR}/coco \
  --arch fasterrcnn_resnet50_fpn \
  --batch_size $BATCH_SIZE \
  --jit \
  -j 0 \
  $ARGS

wait

if [[ ${PLATFORM} != "windows" ]]; then
accuracy=$(grep 'Bbox AP:' ${OUTPUT_DIR}/fasterrcnn_resnet50_fpn_accuracy_log_${PRECISION}_* |sed -e 's/.*Bbox AP//;s/[^0-9.]//g')
echo "fasterrcnn_resnet50_fpn;"Bbox AP";${PRECISION};${BATCH_SIZE};${accuracy}" | tee -a ${OUTPUT_DIR}/summary.log
fi
