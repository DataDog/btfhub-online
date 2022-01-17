FROM golang:1.16-bullseye as builder

RUN apt update && \
    apt install -y \
        gcc       \
        libc-dev

COPY go.mod /code/go.mod
COPY cmd/btfserver/main.go /code/main.go
COPY internal /code/internal
WORKDIR /code
RUN go get -v -d -t ./...
RUN go build -a -mod=mod -ldflags '-extldflags "-static" -w' -o server ./main.go

FROM debian:bullseye-slim

RUN apt update &&    \
    apt install -y bash git gcc cmake libdw-dev apt-transport-https ca-certificates gnupg curl xz-utils

RUN git clone https://github.com/acmel/dwarves && \
    cd dwarves && \
    mkdir build && \
    cd build && \
    cmake -D__LIB=lib .. && \
    make install && \
    ldconfig

RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
   curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - && \
   apt-get update && apt-get install -y google-cloud-sdk

ENV PATH="/app:${PATH}"
ENV GIN_MODE=release

COPY --from=builder /code/server /app/
COPY tools /app/tools

ENV TOOLS_DIR=/app/tools

WORKDIR /app
CMD ./server
