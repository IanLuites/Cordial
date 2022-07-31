# HelloWorld

Example project based on the Protobuf gRPC example: ["helloworld.proto"](https://github.com/grpc/grpc/blob/master/examples/protos/helloworld.proto).

## Quick Start

Start the server:

```shell
$ mix deps.get
$ iex -S mix
```

Test the HTTP module:

```shell
curl -X POST 'http://localhost:3000/helloworld/greeter/say_hello' \
  -H 'content-type: application/json' \
  -d '{"name":"Bob"}'
```

Expected output:

```json
{
  "message": "Hello Bob!"
}
```

## Details

The following components make up the functioning server:

- [schemas.ex](./lib/hello_world/schemas.ex), defining the RPC schemas.
  Generating Elixir modules based on schema.
- [greeter.ex](./lib/hello_world/server/helloworld/greeter.ex), implementation of the greeter service.
- [server.ex](./lib/hello_world/server.ex), exposing the service implementation.

## Notes

The protocol buffer defining the server lacks any `google.http.api` notations.
By default _Cordial_ exposes it based on package, service name, and rpc name.

This functionality can be disabled by setting:

```elixir
http: [expose: :annotated_only]
```

(Or by adding the annotation inside the protocol buffer.)
