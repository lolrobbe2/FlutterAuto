# Create the target directory if it doesn't exist yet
mkdir -p lib/generated

# Run the compiler
protoc --proto_path=./oaa \
       --dart_out=./lib/generated \
       $(find ./oaa -name "*.proto")
