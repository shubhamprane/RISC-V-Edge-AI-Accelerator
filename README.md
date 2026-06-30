# RISC-V NeuroCore — Edge Neural Network Inference via Systolic MAC Array

A fully custom FPGA AI accelerator built from scratch: a 3-stage RV32I pipeline extended with an 8×8 INT8 systolic array coprocessor, running bare-metal MNIST digit classification at **113x the speed** of pure software execution on the same CPU.

---

## What This Is

Most edge ML deployments offload to an existing NPU or rely on a vendor-provided IP block. This project takes a different approach — every layer of the stack is custom, from the RISC-V pipeline itself down to the INT8 quantization scheme and the bare-metal C firmware.

The core idea: dense matrix-vector multiplications dominate MLP inference, and a 2D systolic array can execute 64 MAC operations per clock cycle while a scalar CPU executes one. The FPGA fabric is what makes this practical — the 8×8 PE grid is instantiated as parallel hardware logic, so all 64 multiply-accumulate units operate simultaneously every clock cycle rather than being scheduled sequentially on a CPU core. Coupling the array to a soft-core RISC-V via MMIO lets the CPU act as a lightweight orchestrator — configuring the coprocessor, triggering inference, and reading results — while the FPGA does the heavy arithmetic.

Input gets to the FPGA over UART: a Python host GUI sends 784 bytes representing a 28×28 pixel image at 115,200 baud, which the on-chip `uart_input_buffer` module frames into 32-bit words and writes directly into the input BRAM. Arrival of the 784th byte triggers hardware inference automatically — no CPU intervention needed for the transfer. From there, the coprocessor FSM takes over entirely, streaming weight tiles through the systolic array, applying fused ReLU and bias, rescaling between layers in hardware, and asserting `cop_done` when the ArgMax result is ready.

The result is end-to-end handwritten digit recognition: draw a digit in the GUI, transmit over UART, and the FPGA classifies it in ~2.26 ms with 97.85% accuracy on MNIST — 113× faster than running the same MLP in C on the RISC-V core.

---

## Architecture

```
  Host PC (Python GUI)
       |
       | UART @ 115,200 baud (784 bytes)
       v
  ┌─────────────────────────────────────────────────────────┐
  │                    Nexys A7-100T                        │
  │                                                         │
  │  uart_rx → uart_input_buffer → Input BRAM (100 MHz)    │
  │                                      │  (CDC: toggle)  │
  │                                      ▼                  │
  │  ┌──────────────────────────────────────────────────┐  │
  │  │         RISC-V RV32I Pipeline (10 MHz)           │  │
  │  │         3-stage: IF/ID → EX → MEM/WB            │  │
  │  │                  │                               │  │
  │  │           MMIO @ 0xC000_0000                     │  │
  │  │                  │                               │  │
  │  │  ┌───────────────▼──────────────────────────┐   │  │
  │  │  │       Coprocessor FSM (11 states)        │   │  │
  │  │  │  Tile stream → 8×8 Systolic Array        │   │  │
  │  │  │  ReLU + Bias fused → INT32→INT8 rescale  │   │  │
  │  │  │  → Layer 2 → 4-stage ArgMax tree         │   │  │
  │  │  └──────────────────────────────────────────┘   │  │
  │  └──────────────────────────────────────────────────┘  │
  │                                                         │
  │  7-seg: predicted digit class                          │
  │  16-LED: confidence bar (winner margin score)          │
  └─────────────────────────────────────────────────────────┘
```

### Pipeline

A 3-stage in-order RV32I soft-core (IF/ID, Execute, MEM/WB) runs all C firmware and issues MMIO writes to the coprocessor. No OS, no FPU, no off-chip memory.

### Coprocessor

An 11-state FSM decodes 10 MMIO configuration registers, streams weight/input tiles to the systolic array, handles inter-layer INT32→INT8 requantization in hardware, and drives the ArgMax unit. Triggered by a single write to `COP_START`.

### Systolic Array

An 8×8 grid of 64 processing elements, each performing a fused `acc += a_in * w_in` each clock cycle. Weights are preloaded; activations stream column-wise. A falling-edge detector on `a_valid` triggers output capture without additional counters, adding bias and ReLU in the same register stage.

### Quantization

A Python post-training quantization pipeline trains a float32 2-layer MLP (784→128→10) on MNIST with scikit-learn, then runs a grid search over `w1_scale`, `w2_scale`, and `inter_shift` to find the INT8 parameters that maximize hardware inference accuracy. The optimal shift (`inter_shift = 11`) is calibrated jointly across both layers because Layer 2's bias scale depends on Layer 1's output scale. Quantized accuracy: **97.85%** on the 10,000-sample MNIST test set.

---

## Performance

| Metric | Value |
|---|---|
| Architecture speedup (HW vs RISC-V C) | **113.62×** |
| Hardware inference latency | **2.26 ms** @ 50 MHz |
| Software baseline latency (same CPU) | 257.05 ms |
| Peak throughput | 3.2 GMACs/s |
| Effective throughput (avg) | 125.4 MMACs/s |
| MNIST accuracy (INT8 quantized) | 97.85% |
| Timing (WNS / WHS) | +5.963 ns / +0.044 ns |

### FPGA Resource Utilization (Nexys A7-100T, XC7A100T)

| Resource | Used | % |
|---|---|---|
| LUT | 14,288 | 22.5% |
| FF | 5,068 | 4.0% |
| BRAM | 34.5 tiles | 25.6% |
| DSP | 1 | 0.42% |

The near-zero DSP usage (1 slice vs. the 64 one might expect) results from the systolic array being built from LUT-based multiply-accumulate logic. This was a conscious tradeoff to keep the PE architecture transparent and tool-independent.

---

## Repository Layout

```
.
├── rtl/
│   ├── core/            # 3-stage RV32I pipeline (IF_ID.v, execute.v, pipeline.v, wb.v)
│   ├── coprocessor/     # Systolic array (systolic_array.v, pe.v), ArgMax, coprocessor FSM
│   ├── memory/          # Dual-port BRAMs (weight, input, output, bias)
│   └── top/             # Top-level integration, 7-seg and LED controllers, UART
├── sw/
│   ├── c/               # Bare-metal firmware (test_full_inference.c, bench_perf.c, cop_mmio.h)
│   └── asm/             # Startup (ctr0.s) and linker script
├── sim/
│   ├── testbenches/     # RTL testbenches (tb_systolic_corrected.v, tb_coprocessor_8x8.v, ...)
│   └── golden/          # NumPy golden model for co-simulation
├── final/
│   ├── python/          # Training + quantization (train_mnist.py), GUI (draw_and_send.py)
│   ├── rtl/             # Final synthesis-ready RTL snapshot
│   ├── neurocore.bit    # Prebuilt bitstream for Nexys A7-100T
│   └── BENCHMARK_REPORT.md
├── data/                # BRAM initialization files (weights.mem, bias.mem, input.mem)
└── constraints/         # Nexys A7 XDC pin constraints
```

---

## Running the Demo

### Prerequisites

- Vivado 2023.x (or later) for synthesis/implementation
- RISC-V toolchain: `riscv32-unknown-elf-gcc`
- Python 3.9+ with: `numpy`, `scikit-learn`, `pyserial`, `Pillow`

### 1. Program the FPGA

A prebuilt bitstream is available at `final/neurocore.bit`. Load it with Vivado Hardware Manager or `openFPGALoader`:

```bash
openFPGALoader -b nexysA7 final/neurocore.bit
```

### 2. (Optional) Rebuild the firmware

```bash
cd sw
make          # produces imem.hex and dmem.hex, loaded via $readmemh at synthesis
```

### 3. (Optional) Retrain and re-quantize

```bash
cd final/python
python train_mnist.py
# Outputs: weights.mem, bias.mem (copied to data/ and project root)
```

### 4. Run the host GUI

```bash
cd final/python
python draw_and_send.py COM5        # Windows
python draw_and_send.py /dev/ttyUSB0   # Linux
```

Draw a digit on the canvas, click **Send to FPGA**, and read the predicted class off the 7-segment display.

---

## Key Design Decisions

**Hardware requantization.** Inter-layer INT32→INT8 scaling was moved from RISC-V firmware into the coprocessor FSM. Doing this in software would stall the CPU for hundreds of cycles per inference and defeat the purpose of the accelerator.

**Post-training grid search over QAT.** Quantization-aware training is expensive and hard to implement in a bare-metal-friendly way. A two-minute PTQ grid search over `(w1_scale, w2_scale, inter_shift)` found parameters achieving 97.85% — close to the float32 baseline (~98%) with zero training overhead.

**Toggle-register CDC.** The UART receive domain runs at 100 MHz; the CPU/coprocessor domain runs at 10 MHz. A toggle register on `buf_ready` plus a 3-stage synchronizer on the slow clock cleanly crosses the domain boundary without a FIFO.

**Unified input BRAM.** The same dual-port BRAM holds raw pixel inputs for Layer 1 and quantized activations for Layer 2. The coprocessor FSM writes scaled L1 outputs back into Port B after the first layer completes, eliminating a dedicated intermediate buffer.

---

## Contributors

| Member | Contribution |
|---|---|
| Avinash Choudhary | MMIO decoder, coprocessor FSM, BRAM modules, top-level FPGA integration |
| Samvit Shandilya | INT8 quantization pipeline, inference C firmware, cycle-count benchmarks, Python golden models |
| Shubham Rane | UART RX state machine, input buffer, MMIO header, host GUI, LED controller |
| Varun Batra | 1D vector MAC engine, 8×8 systolic array and PE modules, zero-logit bug fix |
| Ved Jani | ArgMax tournament tree, 7-segment controller, performance counter CSR, co-simulation testbenches |

Course project under Prof. Lokesh Siddhu — Digital Design & Computer Architecture, IIT Guwahati (2025–26).
