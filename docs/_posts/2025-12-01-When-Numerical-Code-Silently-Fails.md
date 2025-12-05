---
layout: blog
title: "When Numerical Code Silently Fails: An Illustrative Example"
discussed: finding exception-handling failures with EXCVATE, opaque compiler transformations, the idiosyncracies of the x86 MAXSS instruction
---
As investment in HPC and AI grows, so too does the importance of ensuring the correctness of the numerical code underlying these technologies. [High-profile failures of numerical software deployed in mission-critical scenarios](https://www-users.cse.umn.edu/~arnold/disasters/) highlight the disastrous costs of incorrectness. One understudied source of incorrectness is the inconsistent handling of the exceptions defined in the IEEE 754 Standard. This is especially relevant today given the landscape of modern computing: GPUs are ubiquitous and, spurred by the growing computational demands of AI, they ship with ever-evolving generations of under-documented hardware accelerators (e.g., tensor cores, matrix cores) that operate on exception-prone/low-precision data types and that prioritize performance over correctness. When exception handling bugs remain an undetected failure mode in deployed code, they can appear nondeterministically in production. This can lead to disastrous consequences. For example, during a 2020 showcase of self-driving car technology, a mishandled `NaN` value in one race car's system led to a loss of steering, [causing the car to smash into a wall](https://www.reddit.com/r/formula1/comments/jk9jrg/comment/gai295l/?context=1).

Today, no existing tool is designed to detect failures in exception handling. To address this gap is to convert latent, nondeterministic runtime failures into immediate, actionable diagnostics. In doing so, debugging costs are dramatically reduced while shifting the detection of potentially catastrophic errors from deployment to development.

In this post, I’ll explore how my work on EXCVATE accomplishes this via an illustrative example. Along the way, we will see:
1. An interesting case of an exception-handling failure stemming from the idiosyncratic behavior of the x86 `maxss` instruction.
2. A high-level overview of the techniques I implemented in EXCVATE to find such failures.
3. How the opaque nature of different compiler transformations can have surprising and unintended consequences for exception handling in floating-point programs.

The following is adapted from the tutorial I bundled along with the source code [available here](https://github.com/ucd-plse/EXCVATE). The full paper is [available here](/assets/pdf/excvate.pdf)
## A simple piece of numerical code hides a latent exception-handling failure
Consider the squared hinge loss, given by:

$$L(y,t) = max(0, 1-yt)^2$$

We’ll test the following two Fortran implementations:
```
module squared_hinge_losses
    implicit none

    contains

        real function squared_hinge_loss1(y, t)
            real :: y, t
            squared_hinge_loss1 = (max(0.0, 1-y*t))**2
        end function

        real function squared_hinge_loss2(y, t)
            real :: y, t
            squared_hinge_loss2 = (max(1-y*t, 0.0))**2
        end function

end module
```

Both of these functions calculate the same quantity with the only difference being in the order of the operands for the `max` intrinsic function; _their results should be identical_. __However, as we will soon discover with EXCVATE, one of these implementations has a latent exception-handling failure when compiled with `gfortran`.__
## Using EXCVATE to find latent failures in exception handling

![](/assets/img/Pasted image 20251204171151.png)

EXCVATE is made up of three components, each of which is implemented as a plugin for the [PIN binary instrumentation framework](https://www.intel.com/content/www/us/en/developer/articles/tool/pin-a-dynamic-binary-instrumentation-tool.html).
### Step 0: EXCVATE’s inputs
EXCVATE requires two inputs:
1. One or more binaries that exercise the functions we are testing. In the case of BLAS libraries, these are the developer-written regression tests bundled with the source code. Here, the tutorial comes with a simple test binary that runs the squared hinge loss functions on a handful of simple inputs.
2. A set of function prototypes. These are simple text files describing the input and output parameters of the functions to be tested. For these squared hinge loss functions, they look like this:
```
y       r   32  in      1
t       r   32  in      1
result  r   32  return  1
```

This indicates to EXCVATE that there are two 32-bit real inputs we are naming `y` and `t` and a one 32-bit real return value we are naming `result`.
### Step 1: The Execution Selector collects a set of representative inputs for the functions under test
We invoke the Execution Selector on the command line like so, providing the path to the prototype files and the path to the creatively-named test binary, `test`:
```
execution_selector -f prototypes/gfortran/ -- ./test
```

We will see the stdout from the normal execution of the `test` binary followed by these summary statistics from EXCVATE:

```
    saved 1 __squared_hinge_losses_MOD_squared_hinge_loss2 executions for replay
    saved 1 __squared_hinge_losses_MOD_squared_hinge_loss1 executions for replay
    saved 2/8 executions for replay
```

Note that we saved 1 execution for each of the functions under test. This is because there is no control flow in either of these functions so a single execution using one of the test inputs suffices for each in order to cover all executable paths.
### Step 2: The Exception Spoofer overwrites the output of x86 instructions with `NaN` to see if they are handled incorrectly
#### Design and Motivation
The strategy here is informed by two key points:
1. It can be tricky to devise function inputs that trigger `NaN`-generating exceptions in specific instructions.
2. Most `NaN`-generating exceptions are handled correctly, meaning that the generated `NaN` is propagated to the function’s output, thereby signaling that something went wrong.

Point (2) means that, when your goal is finding exception-handling failures, taking on the work involved in Point (1) to trigger these exceptions is often wasted effort. Instead, the Exception Spoofer does the following:
```
For each selected function execution:
	For each instruction execution that could trigger a NaN-generating exception
		Replay the function execution
		Spoof the exception by overwriting the instruction's output with a NaN
		Raise a warning if handled incorrectly
```
#### Seeing it in action
We invoke the Exception Spoofer on the command line like so:
```
exception_spoofer -f prototypes/gfortran/ -- ./test
```

And we see the following stdout:
```
** replaying function executions with nan overwrites
    __squared_hinge_losses_MOD_squared_hinge_loss2
               Spoofed Exceptions: 3
      Exception-Handling Failures: 0
                     Failure Rate: 0.0000%
                       Miss Count: 0
    __squared_hinge_losses_MOD_squared_hinge_loss1
               Spoofed Exceptions: 3
      Exception-Handling Failures: 2
                     Failure Rate: 66.6667%
                       Miss Count: 0
```
The Spoofed Exception count for each is 3 because there are three possible instructions executed that could cause a `NaN`-generating exception: one subtraction and two multiplications. It looks like the Exception Spoofer raised two warnings for potential exception-handling failures in `squared_hinge_loss1`.
### Step 3: The Input Generator reifies spoofed exceptions with with a combination of taint tracking and SMT solving
#### Design and Motivation
Because the Exception Spoofer has issued warnings for two potential exception-handling failures in `squared_hinge_loss1`, let us run the third component of EXCVATE to find which, if any of them, constitute true bugs. For a true buggy case, EXCVATE must create an input that satisfies the following:
1. The input must trigger the spoofed `NaN`-generating exception
2. The input must preserve the pathological control flow that resulted in failed exception handling.

Point (1) follows from the fact that the exception spoofer may have spoofed an exception in an instruction where, based on previous operations constraining the values of its operands, a `NaN`-generating exception is actually impossible. The Input Generator must rule out such cases.

Point (2) follows from the fact that it is possible that inputs satisfying point (1) may have side effects on the control flow that end up causing proper handling. The Input Generator must rule out such cases.

The Input Generator accomplishes this by doing the following:
```
For each warning:
	Apply taint to each FP input
	Replay the execution with the specific spoof that caused the warning
	For each instruction executed with tainted operands
		Add a semantically-equivalent constraint to an SMT query
	Give query to an SMT solver
	If satisfiable:
		Run program with generated input
```
#### Seeing it in action
```
input_generator -f prototypes/gfortran/ -- ./test 
```

We see the following stdout:
```
** attempting to generate inputs that reify exception-handling failures
    __squared_hinge_losses_MOD_squared_hinge_loss1
        4 SAT instances
        4 event traces generated
```
### Step 4: Inspecting the Results
Let us look at the contents of one of the event traces (omitting a few columns for display purposes):
```
(in) y: -1.17549e-38 
(in) t: nan 
(out) result: 0

====================================

Disassembly                        Event   Taint Count    
movss xmm0, dword ptr [rax]        G---    1              
mulss xmm2, xmm0                   -P-r    2              
movss xmm0, dword ptr [rip+0x3cf]  --K-    1              
subss xmm0, xmm2                   -P-r    2              
maxss xmm0, xmm1                   --Kr    1                          
```

At the top, we see the inputs generated by the SMT solver and the output returned by the function; a `NaN` input is resulting in a zero output! To shed some light on what happened, we can inspect the event trace at the bottom which lists all executed instructions where exceptional values were found:
1. First, the `movss` instruction loaded the input NaN from memory into the `xmm0` register. The `G---` event code indicates that this was a "**G**enerate" event as this was the first instruction to see the `NaN`.
2. The `mulss` instruction performed the multiplication `y*t` and stored the result into `xmm2`. The `-P-r` event code indicates that there was both a "**r**ead" event (there was an exceptional value in one of the read operands) and a "**P**ropagate" event. The taint count indicates that after that instruction, EXCVATE was tracking two exceptional values: one in `xmm2` and the other in `xmm0`.
3. The `movss` instruction moved the constant 1 into `xmm0` to prepare for the subtraction. The `--K-` event code inticates that there was a "**K**ill" event which overwrote the `NaN` in `xmm0` that was written there by the initial `movss` instruction. The decremented taint count reflects this.
4. The `subss` instruction performed the subtraction `1-y*t` and stored the result into `xmm0`. The instruction propagated the `NaN`. The event code and taint count reflect this.
5. The `maxss` instruction performed the max operation. The `--Kr` event code indicates that there was both a "**r**ead" event and a "**K**ill" event which overwrote the NaN in `xmm0` that was written there by the previous `subss` instruction. The decremented taint count reflects this.

This concludes the executed instructions that had exceptional values. While the non-zero taint count in the last row of the event trace highlights the fact there is still one `NaN` in the `xmm2` register, the x86 calling convention dictates that floating-point function return values are passed in `xmm0`; thus, we can deduce that the 0 return value was written by the `maxss` instruction and no further instructions read from the `xmm2` register.
## Conclusions
[From the documentation of the `maxss` instruction](https://www.felixcloutier.com/x86/maxss):
> __If only one value is a NaN (SNaN or QNaN) for this instruction, the second source operand, either a NaN or a valid floating-point value, is written to the result.__ If instead of this behavior, it is required that the NaN from either source operand be returned, the action of MAXSS can be emulated using a sequence of instructions, such as, a comparison followed by AND, ANDN, and OR.

While this default behavior is questionably correct (it does not adhere to the definition of `maximum` provided in the [IEEE-754 2019 standard](https://standards.ieee.org/ieee/754/6210/) which mandates propagation in the case of any quiet `NaN` operands), this could be forgiven if either `gfortran` translated the Fortran `max` intrinsic into the IEEE-compliant sequence of instructions alluded to by the documentation (it does not), or at the very least if `gfortran` generated a `maxss` instruction whose operand order was consistent with what was written in the source code...

However, if the latter were true, we would expect `squared_hinge_loss2` to have the exception-handling failure found by EXCVATE and not `squared_hinge_loss1`. To see this, let's consider `squared_hinge_loss1` for which the `max` operation in the source code has a constant as the first operand. Since the second operand is the only potential source for a `NaN`, we could assume from the `maxss` documentation that writing the source in this way ensures propagation. But we saw that the assembly generated by `gfortran` actually places the result of the subtraction (`subss xmm0, xmm2`) as the _first_ operand to the max instruction (`maxss xmm0, xmm1`). The compiler reversed the order of the operands! Hence, `squared_hinge_loss1` has an unexpected exception-handling failure.

Furthermore, since EXCVATE did not find a failure in `squared_hinge_loss2`, we can deduce that the operand reversal in the translation to assembly happened there as well, thus leading to an order of `maxss` operands that actually ensured propagation. Interesting!

Even more interesting: exception handling behavior can change from one compiler to another. If you  substitute `ifx` for `gfortran` _both functions will have the exception handling failure._ It seems that `ifx` is determined to set the operand order so that, as written, there will always be an exception-handling failure in the code...