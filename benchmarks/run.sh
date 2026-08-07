#!/bin/bash

set -e

JAVA=$CI_PROJECT_DIR/jdk/bin/java
JAVAC=$CI_PROJECT_DIR/jdk/bin/javac

echo "Using:"
$JAVA -version

$JAVAC HelloWorld.java
$JAVA HelloWorld