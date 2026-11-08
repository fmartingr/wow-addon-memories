# Build from the repository root: docker build -f server/Dockerfile -t memories-server .
FROM golang:1.27@sha256:e519d3b0a5b285e5aa53ab9eef02bc6bbb9cb04608389b743a136a9ce75f0d1e AS build
WORKDIR /src/server
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/ ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags=-s -o /out/memories-server ./cmd/memories-server
# The image has no shell, so the data folder is made here. A new named volume copies the owner of the image folder,
# which lets the nonroot user (65532) write to it. The server makes each file 0600 and each folder below it 0700.
RUN mkdir /out/data && chown 65532:65532 /out/data

FROM gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab
WORKDIR /app
COPY --from=build /out/memories-server /app/memories-server
COPY web/index.html web/app.js web/kinds.js web/style.css /app/web/
COPY --from=build --chown=65532:65532 /out/data /data
ENV MEMORIES_WEB_DIR=/app/web \
    MEMORIES_DATA_DIR=/data \
    MEMORIES_ADMIN_ADDR=0.0.0.0:8081
VOLUME /data
USER nonroot
EXPOSE 8080
ENTRYPOINT ["/app/memories-server"]
