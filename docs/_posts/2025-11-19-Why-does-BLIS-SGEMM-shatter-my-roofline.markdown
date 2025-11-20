---
layout: blog
title:  "Why does BLIS SGEMM shatter my roofline?"
discussed: roofline plots, my trash test system, matrix multiplication, hot vs cold caches
---
## Deriving the roofline for my test machine
The theoretical peak performance of my [i7-3770K](https://www.intel.com/content/www/us/en/products/sku/65523/intel-core-i73770k-processor-8m-cache-up-to-3-90-ghz/specifications.html) processor (measured in GFLOPs/second) can be calculated according to (Processor Frequency in GHz) x (# of Operations per cycle) x (# of Operands per Register) x (# of Physical Cores):
- The processor frequency is 3.5 GHz, or 3.9 GHz with Turbo Boost.
- The processor does not support FMA. The reciprocal throughput of single precision addition and multiplication instructions (ADDSS/ADDPS/VADDSS/VADDPS and MULSS/MULPS/VMULSS/VMULPS) is 1. This means that a new instruction can start executing 1 clock cycle after a previous instruction, assuming the values of its operands are not dependent on any previous instructions in the pipeline. The processor has separate execution ports for addition and multiplication instructions so they may be executed on the same clock cycle. → # of operations per cycle is 2.
- The processor has 256 bit vector registers → # of Operands per Register is 256/32 = 8.
- The processor has 4 physical cores.

→Plugging these values in yields a peak GFLOPs/second of 224 or 249.6 with Turbo Boost.

The theoretical peak memory bandwidth (measured in GB/second) can be calculated according to (Memory Bus Width in Bytes) x (Memory Transfer Rate in MT/second) x (# active channels) / 1000:
- The memory bus width is 8 bytes.
- The memory transfer rate is 1333 MT/second.
- The memory is dual-channel.

→Plugging these values in yields a peak memory bandwidth of 21.328 GB/second.

## How we’re measuring SGEMM performance
Consider C = AB + C

__Compiling BLIS__: We compile for the `sandybridge` architecture for which BLIS has a pre-configured multithreaded build.

__Spanning shapes and sizes:__ Let’s run the BLIS implementation of SGEMM spanning different shapes and sizes per the following pseudo code:
```
int min_dim = 16;
int max_dim = 1024;
for ( int m = min_dim; m < max_dim; m = 2*m ){
	for ( int n = min_dim; n < max_dim; n = 2*n ){
		for ( int k = min_dim; k < max_dim; k = 2*k ){
			...
		}
	}
}
```

__Measuring performance:__ For each parameterization, we will measure the FLOPs/second using $$\frac{2mnk}{t}$$ where $$t$$ is the minimum execution time in seconds over 10 executions; this is intended to account for run-to-run performance variability and to exclude any outliers due to cold caches. Subsequent multiplication by $$10^{-9}$$ gives us GFLOPs/second.

__Calculating arithmetic intensity__: We will calculate arithmetic intensity by dividing the GFLOPS/second measured above by $$4(2mn + mk + kn)$$, i.e., $$2mn$$ reads/writes of C, $$mk$$ reads of A, $$kn$$ reads of B, and each element is a 4 byte float.

__Initializing the A and B matrices:__ Elements of A and B are initialized with values drawn from $$U(0,1)$$.

__Additional Information:__ To get an idea of how “rectangular” the matmul is, we will also measure the maximum dimension ratio. If m=k=n (all matrices are square), this quantity will be 1. If m=1, k=2, and n=3, this quantity will be 3.

## An anomaly in the results plot

![](/assets/img/Screenshot from 2025-11-17 17-31-43.png)
__Why do some parameterizations of BLIS SGEMM surpass the theoretical DRAM Memory-bound?__

From the color of the markers, we can see these are rectangular GEMMs. Zooming in, there are three offenders. Described as (m,k,n) tuples, they are:
```
( 512, 16, 1024)
(1024, 16,  512)
(1024, 16, 1024)
```
Of note: the analogous rectangular GEMM for the next largest size of k – the tuple `(1024, 32, 1024)` – is _below_ the roofline; let’s gather more data by looking at smaller sizes of k.
## After generating more data, patterns emerge
Lowering the `min_dim` to 2 and rerunning our experiments, patterns emerge for memory-bound GEMMs:

![[Screenshot from 2025-11-17 17-48-26.png]]Now, our offenders are:
```
(1024, 2, 1024)  (1024, 4, 1024)  (1024, 8, 1024)  (1024, 16, 1024)
( 512, 2, 1024)  ( 512, 4, 1024)  ( 512, 8, 1024)  ( 512, 16, 1024)
(1024, 2,  512)  (1024, 4,  512)  (1024, 8,  512)  (1024, 16,  512)
( 512, 2,  512)  ( 512, 4,  512)  ( 512, 8,  512)
( 256, 2, 1024)  ( 256, 4, 1024)  ( 256, 8, 1024)
( 256, 2,  512)  ( 256, 4,  512)  ( 256, 8,  512)
( 512, 2,  256)  ( 512, 4,  256)  ( 512, 8,  256)
(1024, 2,  256)  (1024, 4,  256)
```
I feel confident in the theoretical DRAM memory bound that I calculated. __The issue could lie with either the calculation of arithmetic intensity or some subtleties with the faster cache memory.__

Let’s test the latter.
## Controlling for cache behavior
To control for cache behavior, we will execute each GEMM with a cold cache. Before each GEMM execution, we will allocate a buffer that exceeds the capacity of our 8 MiB Last-Level Cache and loop over the elements of that buffer with some trivial read or write. If we wanted more performant flushing, we could be more precise about the alignment of the buffer and divide it up into cache lines so that we only touch one element per cache line, but this will suffice for now. Rerunning our experiments, we get the following:

![[Screenshot from 2025-11-18 14-24-38.png]]
I think we’ve found our culprit! Let’s visualize how each GEMM benefits from a warm cache by plotting (GFLOPs per second with warm cache)/(GFLOPs per second with cold cache):

![[Screenshot from 2025-11-18 15-25-50.png]]
Caching appears to more dramatically benefit GEMMs with less arithmetic intensity.

Is it true that caching also benefits square GEMMs more than rectangular GEMMs, something that the gradient of colors in this plot might suggest?
No, I don’t think so. 

