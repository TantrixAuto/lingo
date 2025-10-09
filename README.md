This is a standalone project that uses yantra.

# Steps to build
0. First checkout and build yantra

1. clone the repo:
```
git clone git@github.com:TantrixAuto/lingo.git
```

2. Checkout the develop branch
```
git checkout develop
```

3. create a build directory
```
mkdir build
cd build
```

4. Copy ycc (or ycc.exe) into this build directory

5. create makefiles
```
cmake ..
```

6. build the project
```
cmake --build .
```

7. run the executable
```
bin/lingo -f ../test.lingo
```
