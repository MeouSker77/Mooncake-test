#!/bin/bash

set -e

source "$(dirname "$(readlink -f "$0")")/../scripts/allocator_build_common.sh"

# Check for flags
USE_NVCC=false
USE_HIPCC=false
USE_MCC=false
USE_MACA=false
CI_BUILD=false

if [[ "$1" == "--use-nvcc" ]]; then
    USE_NVCC=true
    shift
elif [[ "$1" == "--use-hipcc" ]]; then
    USE_HIPCC=true
    shift
elif [[ "$1" == "--use-mcc" ]]; then
    USE_MCC=true
    shift
elif [[ "$1" == "--use-maca" ]]; then
    USE_MACA=true
    shift
elif [[ "$1" == "--ci-build" ]]; then
    CI_BUILD=true
    shift
fi

# Get output directory from command line argument, default to current directory
OUTPUT_DIR=${1:-.}

prepare_allocator_build_env "$OUTPUT_DIR" "${2:-}"

echo "Building nvlink allocator to: $OUTPUT_DIR"

CPP_FILE="${SCRIPT_DIR}/nvlink_allocator.cpp"

find_cuda_include_dir() {
    local candidates=()
    if [ -n "${CUDA_HOME:-}" ]; then
        candidates+=("${CUDA_HOME}/include")
    fi
    candidates+=("/usr/local/cuda/include")
    for dir in /usr/local/cuda-*/include; do
        candidates+=("$dir")
    done

    for dir in "${candidates[@]}"; do
        if [ -f "${dir}/cuda.h" ]; then
            echo "$dir"
            return 0
        fi
    done
    return 1
}

find_cuda_driver_lib_dir() {
    local candidates=()
    if [ -n "${CUDA_HOME:-}" ]; then
        candidates+=(
            "${CUDA_HOME}/lib64/stubs"
            "${CUDA_HOME}/targets/x86_64-linux/lib/stubs"
            "${CUDA_HOME}/lib64"
        )
    fi
    candidates+=(
        "/usr/local/cuda/lib64/stubs"
        "/usr/local/cuda/targets/x86_64-linux/lib/stubs"
        "/usr/local/cuda/lib64"
    )
    for dir in /usr/local/cuda-*/lib64/stubs /usr/local/cuda-*/targets/x86_64-linux/lib/stubs /usr/local/cuda-*/lib64; do
        candidates+=("$dir")
    done

    for dir in "${candidates[@]}"; do
        if [ -f "${dir}/libcuda.so" ]; then
            echo "$dir"
            return 0
        fi
    done
    return 1
}

CUDA_INCLUDE_DIR=$(find_cuda_include_dir || true)
CUDA_DRIVER_LIB_DIR=$(find_cuda_driver_lib_dir || true)
CUDA_INCLUDE_FLAGS=""
CUDA_DRIVER_LDFLAGS=""

if [ -n "$CUDA_INCLUDE_DIR" ]; then
    CUDA_INCLUDE_FLAGS="-I${CUDA_INCLUDE_DIR}"
fi
if [ -n "$CUDA_DRIVER_LIB_DIR" ]; then
    CUDA_DRIVER_LDFLAGS="-L${CUDA_DRIVER_LIB_DIR}"
fi

# Choose build command based on flags
if [ "$CI_BUILD" = true ]; then
    nvcc "$CPP_FILE" -o "$OUTPUT_DIR/nvlink_allocator.so" -shared -Xcompiler -fPIC \
        ${CUDA_INCLUDE_FLAGS} ${INCLUDE_FLAGS} ${CUDA_DRIVER_LDFLAGS} -lcuda -DUSE_CUDA=1
elif [ "$USE_NVCC" = true ]; then
    # Regular nvcc build with cuda linking
    nvcc "$CPP_FILE" -o "$OUTPUT_DIR/nvlink_allocator.so" -shared -Xcompiler -fPIC \
        ${CUDA_INCLUDE_FLAGS} ${INCLUDE_FLAGS} ${CUDA_DRIVER_LDFLAGS} -lcuda -DUSE_CUDA=1
elif [ "$USE_HIPCC" = true ]; then
    hipify-perl "$CPP_FILE" > "${OUTPUT_DIR}/nvlink_allocator.cpp"
    hipcc "$OUTPUT_DIR/nvlink_allocator.cpp" -o "$OUTPUT_DIR/nvlink_allocator.so" -shared -fPIC -lamdhip64 -I/opt/rocm/include ${INCLUDE_FLAGS} -DUSE_HIP=1
elif [ "$USE_MCC" = true ]; then
    mcc "$CPP_FILE" -o "$OUTPUT_DIR/nvlink_allocator.so" --shared -fPIC -lmusa -I/usr/local/musa/include ${INCLUDE_FLAGS} -DUSE_MUSA=1
elif [ "$USE_MACA" = true ]; then
    MACA_ROOT=${MACA_HOME:-/opt/maca}
    g++ "$CPP_FILE" -o "$OUTPUT_DIR/nvlink_allocator.so" --shared -fPIC \
        -I"${MACA_ROOT}/include" ${INCLUDE_FLAGS} \
        -L"${MACA_ROOT}/lib64" -L"${MACA_ROOT}/lib" -lmcruntime -DUSE_MACA=1
else
    # Default g++ build
    g++ "$CPP_FILE" -o "$OUTPUT_DIR/nvlink_allocator.so" --shared -fPIC \
        ${CUDA_INCLUDE_FLAGS} ${INCLUDE_FLAGS} ${CUDA_DRIVER_LDFLAGS} -lcuda -DUSE_CUDA=1
fi

if [ $? -eq 0 ]; then
    echo "Successfully built nvlink_allocator.so in $OUTPUT_DIR"
else
    echo "Failed to build nvlink_allocator.so"
    exit 1
fi
