---
layout: blog
title: "Short Update: Actually Understanding NVIDIA's ESC Calculation"
discussed: misleading toy examples, hindsight being 20/20, lessons for the future
---
About a month ago, I wrote [a short blog post]({% post_url 2025-12-03-Misunderstanding-NVIDIAs-ESC-calculation %}) describing my attempt to manually apply NVIDIA’s ESC algorithm to a simple example I contrived. This was in an attempt to better understand how NVIDIA is deploying “Ozaki-style emulation” in the latest versions of cuBLAS. There was a problem though: while the methodology described in [the whitepaper](https://arxiv.org/pdf/2511.13778) is described as assuring at least double-precision accuracy for DGEMM, my calculations on the simple example yielded what appeared to be intolerable amounts of error.

Since then, I got in contact with someone from NVIDIA who helpfully cleared up my confusion that stemmed from a simple misunderstanding. The corrected results show that ESC clearly maintains safety with respect to the quality of the answer. _At the same time, they also highlight the performance left on the table due to the potentially huge overhead of maintaining safety in this way._

The below assumes that the reader has made a pass over [the original blog post]({% post_url 2025-12-03-Misunderstanding-NVIDIAs-ESC-calculation %}). Check that out first for context and see if you can spot the blunder!
## Where I went wrong in my understanding

Check out this phrase I typed in my initial post:

> The goal of the ESC calculation is to estimate the number of extra bits needed to achieve FP64 accuracy for the dot product

Extra. EXTRA. The 13 required bits that I calculated for my simple example are _extra bits on top of the original representation’s 53 mantissa bits_.

It is so clear in hindsight: if the goal is to maintain double-precision accuracy, one cannot lose any of the information in the original mantissa bits. This is the type of thing that, once understood, reads as painfully obvious (though implied) when going over the whitepaper again. I found the phrasing unclear (obviously). An equation would have been super helpful for me, say…
<div class="equation">$$\text{Number of INT8 slices} = \bigg\lceil\frac{1 \text{ implicit bit}+ 52 \text{ mantissa bits} + ESC + 1 \text{ carry bit}}{8}\bigg\rceil$$</div>
…but, as it is, this info is sort of scattered about the section. 

## What should have happened in the example I proposed

For reference, here’s the Hadamard product from my example:

![](/assets/img/Pasted image 20251125165706.png)

Based on my misunderstanding, I used only the ESC of 12 and the 1 carry bit, thereby miscalculating that cuBLAS would use __two__ INT8 slices per element in the Hadamard product operands, truncating the $$1.0\times2^{-8}$$ elements to zero like so:

![](/assets/img/Pasted image 20251125172810.png)

I then showed that one needs a minimum of __three__ INT8 slices to calculate a full fidelity output, which looks like this:
![](/assets/img/Pasted image 20251125180415.png)

Based on the correct formula above, what cuBLAS would actually do is use __nine__ INT8 slices. Given that the mantissa for each of the values can be represented with a single bit, this is massive overkill. Most of the INT8 slices are all zeros! Still, this is a toy example. In any realistic case, all those mantissa bits would need to be represented.

## Note to future self

Toy examples are an essential tool for building intuitive understanding. But, if in working through a toy example one encounters unintuitive results, a more realistic example can shed some light. I am sure that I would have clarified my own earlier misunderstanding if I had started working through an example with more than 1 mantissa bit.