Creating Deployment Packages  

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

Running the distro-less Java will return:

```sh
[rhel9@localhost test]$ podman ps
CONTAINER ID  IMAGE
aa15667fce3a  localhost/distroless-java:latest
```

```sh
[rhel9@localhost test]$ podman exec -it aa15667fce3a  bash
Error: crun: executable file `bash` not found in $PATH: No such file 
or directory: OCI runtime attempted to invoke a command that was not found
```

> Now the Java application runs in an image with a greately shrink surface for attacks. 