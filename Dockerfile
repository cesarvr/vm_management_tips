# STAGE 1: Standard UBI image with full tools. 
# The main idea is to reduce the surface of attack by removing the build tools from the image.

FROM ubi9/openjdk-21 AS builder

# We use root here, but don't worry its scope ends on line 15.
USER root

WORKDIR /build
COPY Main.java .
# Compile the native Java class into a bytecode runner
RUN javac Main.java

# STAGE 2: Secure Production Deployment (No Shells, No DNF, No Vim)
FROM registry.access.redhat.com/ubi9/openjdk-21-runtime:1.24 
# Copy the compiled .class file from the builder stage straight to production
COPY --from=builder /build/Main.class /app/Main.class
WORKDIR /app
# Run using the explicit vector execution array syntax
ENTRYPOINT ["java", "Main"]