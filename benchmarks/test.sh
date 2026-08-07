#!/bin/bash

echo "===== Benchmark test started ====="

echo "Machine:"
hostname

echo "CPU:"
lscpu | grep "Model name"

echo "Java:"
java -version

echo "Current directory:"
pwd

echo "===== Benchmark test finished ====="