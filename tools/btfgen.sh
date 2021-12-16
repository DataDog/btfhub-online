#!/bin/bash

usage() { echo "Usage: $0 <archive dir> <file01.bpf.o> <optional filter>" 1>&2; exit 1; }

if [ -z "$2" ] || [ -z "$1" ]; then
    usage
fi

obj_cmdline="--object $2"

SCRIPT_DIR=$(realpath $(dirname "$0"))
ARCHIVE_DIR=$(realpath $1)
btfgen=$SCRIPT_DIR/bin/btfgen
echo $btfgen
if [ ! -x "${btfgen}" ]; then
	echo "error: could not find btfgen tool"
	exit 1
fi

function ctrlc ()
{
	echo "Exiting due to ctrl-c..."
  exit 2
}

trap ctrlc SIGINT
trap ctrlc SIGTERM

# clean custom-archive directory
mkdir -p ./custom-archive
find ./custom-archive -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} \;

filter=*
if [ -n "$3" ]; then
  filter=$3
fi

for dir in $(find $ARCHIVE_DIR/ -iregex ".*x86_64.*" -type d | sed "s:$ARCHIVE_DIR\/::g"| sort -u); do
	# uncompress and process each existing input BTF .tar.xz file
	for file in $(find $ARCHIVE_DIR/${dir} -name "*.tar.xz" -wholename "$filter"); do
		dir=$(dirname $file)
		base=$(basename $file)
		extracted=$(tar xvfJ $dir/$base); ret=$?

		dir=${dir/$ARCHIVE_DIR\/}
		out_dir="./custom-archive/${dir}"
		[[ ! -d ${out_dir} ]] && mkdir -p ${out_dir}

		# generate one output BTF file to each input BTF file given
		$btfgen --input=./${extracted} --output=${out_dir} ${obj_cmdline}
		[[ $ret -eq 0 ]] && [[ -f ./${extracted} ]] && rm ./${extracted}
	done
done

tar -czvf btfs.tar.gz -C custom-archive $(ls ./custom-archive/)
rm -rf ./custom-archive
