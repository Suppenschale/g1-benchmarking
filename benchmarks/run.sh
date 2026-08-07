#!/bin/bash

set -e

echo "===== Running HelloWorld test ====="

# Find the JDK built in the previous CI stage
JAVA=$(find "$CI_PROJECT_DIR/jdk/build" -path "*/images/jdk/bin/java" | head -n 1)
JAVAC=$(find "$CI_PROJECT_DIR/jdk/build" -path "*/images/jdk/bin/javac" | head -n 1)

echo "Using Java:"
$JAVA -version

echo "Compiling HelloWorld.java"
$JAVAC benchmarks/HelloWorld.java

echo "Running HelloWorld:"
$JAVA -cp benchmarks HelloWorld

echo "===== Test finished ====="