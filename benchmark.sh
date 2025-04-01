#!/bin/bash

REGEX_BRANCH="testing"
OUTFILE="results_full.csv"
ENGINES='^rust/regex(|-lookbehind)$'

# quit on error
set -e

# Check if git is available
if ! command -v git 2>&1 >/dev/null
then
    echo "Need git to clone repositories, please install it"
    exit 1
fi

# Check if cc is available
if ! command -v cc 2>&1 >/dev/null
then
    echo "Command 'cc' not found, please install the build-essentials package"
    exit 1
fi

# make sure rustup is available and up to date
if ! command -v rustup 2>&1 >/dev/null
then
    if ! command -v curl 2>&1 >/dev/null
    then
        echo "Need curl to install rust, please install curl or install rustup manually"
        exit 1
    fi
    # install rustup
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    . "$HOME/.cargo/env"
else
    # update existing installation
    rustup self update
fi

# update rust
rustup update

# clone regex fork
if [ ! -d "rust-regex" ]
then
    git clone https://github.com/Multimodcrafter/rust-regex.git
fi

# clone rebar fork
if [ ! -d "rebar" ]
then
    git clone https://github.com/Multimodcrafter/rebar.git
fi

# update repos and set toolchains
cd rust-regex
git checkout "$REGEX_BRANCH"
git pull
rustup override set stable
cd ../rebar
git pull
rustup override set stable

# build rebar
cargo install --path .

# build regex engines
rebar build -e "$ENGINES"

# perform sanity check
rebar measure -e "$ENGINES" -f '^test/' --test

# perform benchmark
rebar measure -e "$ENGINES" | tee "../$OUTFILE"