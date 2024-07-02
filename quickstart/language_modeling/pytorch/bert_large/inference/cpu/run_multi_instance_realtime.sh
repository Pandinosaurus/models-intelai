#!/bin/bash

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

ARGS=${ARGS:-""}
num_warmup=${num_warmup:-"20"}
num_iter=${num_iter:-"100"}

#export DNNL_MAX_CPU_ISA=AVX512_CORE_AMX
ARGS="$ARGS --benchmark"
precision=fp32

if [[ "$PRECISION" == *"avx"* ]]; then
    unset DNNL_MAX_CPU_ISA
fi

if [[ "$PRECISION" == "bf16" ]]
then
    precision=bf16
    ARGS="$ARGS --bf16"
    echo "### running bf16 mode"
elif [[ "$PRECISION" == "fp16" ]]
then
    precision=fp16
    ARGS="$ARGS --fp16_cpu"
    echo "### running fp16 mode"
elif [[ "$PRECISION" == "bf32" ]]
then
    precision=bf32
    ARGS="$ARGS --bf32"
    echo "### running bf32 mode"
elif [[ "$PRECISION" == "int8" || "$PRECISION" == "avx-int8" ]]
then
    precision=int8
    ARGS="$ARGS --int8 --int8_bf16"
    echo "### running int8 mode"
elif [[ "$PRECISION" == "fp32" || "$PRECISION" == "avx-fp32" ]]
then
    precision=fp32
    echo "### running fp32 mode"
else
    echo "Please set PRECISION to : fp32, int8, bf32, bf26, avx-int8 or avx-fp32"
fi

rm -rf ${OUTPUT_DIR}/latency_log*
export OMP_NUM_THREADS=4
CORES=`lscpu | grep Core | awk '{print $4}'`
SOCKETS=`lscpu | grep Socket | awk '{print $2}'`
NUMAS=`lscpu | grep 'NUMA node(s)' | awk '{print $3}'`
CORES_PER_NUMA=`expr $CORES \* $SOCKETS / $NUMAS`
INT8_CONFIG=${INT8_CONFIG:-"configure.json"}
BATCH_SIZE=${BATCH_SIZE:-1}
EVAL_DATA_FILE=${EVAL_DATA_FILE:-"${PWD}/squad1.1/dev-v1.1.json"}
FINETUNED_MODEL=${FINETUNED_MODEL:-bert_squad_model}
OUTPUT_DIR=${OUTPUT_DIR:-${PWD}}
EVAL_SCRIPT=${EVAL_SCRIPT:-"./transformers/examples/legacy/question-answering/run_squad.py"}
work_space=${work_space:-${OUTPUT_DIR}}

TORCH_INDUCTOR=${TORCH_INDUCTOR:-"0"}
if [[ "0" == ${TORCH_INDUCTOR} ]];then
    python -m intel_extension_for_pytorch.cpu.launch --ninstances ${NUMAS} --log_dir=${OUTPUT_DIR} --log_file_prefix="./latency_log_${precision}" ${EVAL_SCRIPT} $ARGS --model_type bert --model_name_or_path ${FINETUNED_MODEL} --tokenizer_name bert-large-uncased-whole-word-masking-finetuned-squad  --do_eval --do_lower_case --predict_file $EVAL_DATA_FILE  --per_gpu_eval_batch_size $BATCH_SIZE --learning_rate 3e-5 --num_train_epochs 2.0 --max_seq_length 384 --doc_stride 128 --output_dir ./tmp --perf_begin_iter ${num_warmup} --perf_run_iters ${num_iter} --use_jit --ipex --int8_config ${INT8_CONFIG} --use_share_weight --total_cores ${CORES_PER_NUMA}
else
    echo "Running Bert_Large inference with torch.compile() indutor backend enabled."
    export TORCHINDUCTOR_FREEZING=1
    python -m torch.backends.xeon.run_cpu --ninstances ${NUMAS} --log_path=${OUTPUT_DIR} ${EVAL_SCRIPT} $ARGS --model_type bert --model_name_or_path ${FINETUNED_MODEL} --tokenizer_name bert-large-uncased-whole-word-masking-finetuned-squad  --do_eval --do_lower_case --predict_file $EVAL_DATA_FILE  --per_gpu_eval_batch_size $BATCH_SIZE --learning_rate 3e-5 --num_train_epochs 2.0 --max_seq_length 384 --doc_stride 128 --output_dir ./tmp --perf_begin_iter ${num_warmup} --perf_run_iters ${num_iter} --inductor --int8_config ${INT8_CONFIG} --use_share_weight --total_cores ${CORES_PER_NUMA} 2>&1 | tee ${OUTPUT_DIR}/latency_log_${precision}.log
fi
CORES_PER_INSTANCE=4
TOTAL_CORES=`expr $CORES \* $SOCKETS`
INSTANCES=`expr $TOTAL_CORES / $CORES_PER_INSTANCE`
INSTANCES_PER_SOCKET=`expr $INSTANCES / $SOCKETS`

throughput=$(grep 'Throughput:' ${OUTPUT_DIR}/latency_log* |sed -e 's/.*Throughput//;s/[^0-9.]//g' |awk -v INSTANCES_PER_SOCKET=$INSTANCES_PER_SOCKET '
BEGIN {
        sum = 0;
i = 0;
      }
      {
        sum = sum + $1;
i++;
      }
END   {
sum = sum / i * INSTANCES_PER_SOCKET;
        printf("%.2f", sum);
}')

p99_latency=$(grep 'P99 Latency' ${OUTPUT_DIR}/latency_log* |sed -e 's/.*P99 Latency//;s/[^0-9.]//g' |awk -v INSTANCES_PER_SOCKET=$INSTANCES_PER_SOCKET '
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
    printf("%.3f ms", sum);
}')
echo $INSTANCES_PER_SOCKET
echo "--------------------------------Performance Summary per Socket--------------------------------"
echo ""BERT";"latency";${precision}; ${BATCH_SIZE};${throughput}" | tee -a ${OUTPUT_DIR}/summary.log
echo ""BERT";"p99_latency";${precision}; ${BATCH_SIZE};${p99_latency}" | tee -a ${OUTPUT_DIR}/summary.log
