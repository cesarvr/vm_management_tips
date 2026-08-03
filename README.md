# Building Secure Software

## Creating Deployment Packages  

A good practices is to keep the tools we use for build away from the machine we use in production workload. The idea behind this is to reduce the attack surface for possible bad actors.

For this reason we can use this recommended aproach which consist in dividing the build process in two stages and two separated images. 

First image do the build of the deployable. And the **second image** do the 



```dockerfile 
#STAGE 1 
FROM ubi9/openjdk-21 AS builder

USER root

WORKDIR /build
COPY Main.java .

# Compile the native Java class into a bytecode runner
RUN javac Main.java

# STAGE 2
FROM registry.access.redhat.com/ubi9/openjdk-21-runtime:1.24 
# Copy the compiled .class file from the builder stage straight to production
COPY --from=builder /build/Main.class /app/Main.class
WORKDIR /app
# Run using the explicit vector execution array syntax
ENTRYPOINT ["java", "Main"]
```

Even if this image has the runtime only tools it also includes some tools that make debugging this image easier in productions. Sometimes this tools are necessary and should be part of the risks acceptance. 

As an extra level of harnessing we can trade off easy to observe and debug (unless we have some proper observability tools baked into the deployable package) with an image that include just the minimal J2EE packages and remove everything else including the shell. 

##### Example:

```dockefile 
# We use root here, but don't worry its scope ends on line 10.
USER root  

WORKDIR /build
COPY Main.java .
# Compile the native Java class into a bytecode runner
RUN javac Main.java

# STAGE 2: FROM GCP -> (No Shells, No DNF, No Vim)
FROM gcr.io/distroless/java21:latest 
# Copy the compiled .class file from the builder stage straight to production
COPY --from=builder /build/Main.class /app/Main.class
WORKDIR /app
# Run using the explicit vector execution array syntax
ENTRYPOINT ["java", "Main"]
```

> Now the Java application runs in an image with a greately shrink surface for attacks. 