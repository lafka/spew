integration: integration-server integration-client

integration-client:
	rm -rf ./test/integration/builds/client
	http_proxy=$(HTTP_PROXY) SPEW_TARGETDIRS=./test/integration/targets SPEW_BUILDS=./test/integration/builds spew-build build client/0.0.1

integration-server:
	rm -rf ./test/integration/builds/server
	http_proxy=$(HTTP_PROXY) SPEW_TARGETDIRS=./test/integration/targets SPEW_BUILDS=./test/integration/builds spew-build build server/0.0.1
