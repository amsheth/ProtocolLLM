#!/bin/bash
source ~/envs/llm/bin/activate
# Define the models, protocols, and flags
models=("gpt-4o")
protocols=("i2c" "spi" "uart" "axi")
# protocols=("spi")
use_rag_flags=(true false)
# iter_flag="--iter"

# Iterate over all combinations of models, protocols, and flags
for model in "${models[@]}"; do
    for protocol in "${protocols[@]}"; do
        for use_rag in "${use_rag_flags[@]}"; do
            if [ "$use_rag" = true ]; then
                rag_flag="--use_rag"
            else
                rag_flag=""
            fi

            # Run the command with the current combination
            echo "Running: python main.py --protocol $protocol $rag_flag --model $model"
            python main.py --protocol "$protocol" $rag_flag --model "$model" 
        done
    done
done
