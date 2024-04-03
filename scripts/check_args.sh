#!/bin/bash

# Extract the value of the ARCH argument
ARCH="$1"

# Validate the ARCH value
case $ARCH in
  x86_64|i386|i686)
    echo "Valid architecture provided: $ARCH"
    ;;
  *)
    echo "Unsupported target architecture: $ARCH. Must be one of: x86_64, i386, i686."
    exit 2
    ;;
esac