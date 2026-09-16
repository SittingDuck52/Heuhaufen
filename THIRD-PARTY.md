# Third-party components

## BitCrack (`programm\cuBitCrack.exe`)

Source: https://github.com/brichard19/BitCrack - MIT License.
The binary here was built from that source for CUDA 12.9 (Windows, GitHub Actions);
the build workflow is in https://github.com/SittingDuck52/BitCrack.

```
Copyright (c) 2018 Ben Richard https://github.com/brichard19

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## CUDA runtime (`programm\cudart64_12.dll`)

Part of the NVIDIA CUDA Toolkit and redistributable with applications under the
NVIDIA CUDA Toolkit End User License Agreement (see https://docs.nvidia.com/cuda/eula/).
Copyright (c) NVIDIA Corporation.

## CUDACyclone (not included)

Source: https://github.com/Dookoo2/CUDACyclone - **no license file**, therefore no source and no binary of it
is distributed here. Build it yourself, see the README section "The faster search program".
Windows build and the two changes (fix for skipped keys, resume): https://github.com/SittingDuck52/CUDACyclone