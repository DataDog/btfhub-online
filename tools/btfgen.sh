#!/bin/bash -xe

echo $(date +%s)

usage() { echo "Usage: $0 <file.bpf.o> <kernel>" 1>&2; exit 1; }

if [ -z "$1" ] || [ -z "$2" ]; then
    usage
fi

obj_cmdline="--object $1"

SCRIPT_DIR=$(realpath $(dirname "$0"))
btfgen=$SCRIPT_DIR/bin/btfgen
if [ ! -x "${btfgen}" ]; then
	echo "error: could not find btfgen tool"
	exit 1
fi


function handleBTF() {
  btf=$1
  gsutil cp $btf ./archive

  btf_basename=$(basename $btf)
  btf_dirname=$(dirname $btf)
  extracted=$(tar xvfJ "./archive/$btf_basename"); ret=$?
  dir=${btf_dirname/gs:\/\/btfhub/}
  out_dir="./custom-archive/${dir}"
  [[ ! -d ${out_dir} ]] && mkdir -p ${out_dir}

  # generate one output BTF file to each input BTF file given
  $btfgen --input=./${extracted} --output=${out_dir} ${obj_cmdline}
  [[ $ret -eq 0 ]] && [[ -f ./${extracted} ]] && rm ./${extracted}

  # Delete the BTF
  rm -f "./archive/$(basename $btf)"
}

trap ctrlc SIGINT
trap ctrlc SIGTERM

mkdir -p ./archive
find ./archive -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} \;

# clean custom-archive directory
mkdir -p ./custom-archive
find ./custom-archive -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} \;

filter=""
if [ -n "$2" ]; then
  filter=$2
fi

handleBTF "gs://btfhub/$filter"

tar -czvf btfs.tar.gz -C custom-archive $(ls ./custom-archive)

rm -rf ./custom-archive ./archive
echo $(date +%s)