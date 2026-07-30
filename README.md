# Verification-of-DMA-Direct-Memory-Access-controller-using-System-Verilog

## 📘 Overview
This project implements a Direct Memory Access (DMA) Controller using the AXI4-lite protocol. The DMA controller is designed to autonomously transfer data between memory and peripherals without continuous CPU intervention, improving system efficiency.
# Verification of DMA Controller using SystemVerilog

## 🔹 Features
- **AXI4-Lite Master Interface** for read and write transactions.
- **Configurable Registers**: source address, destination address, transfer length, start/done signals.
- **Finite State Machine (FSM)** to control read requests, data transfers, and write operations.
- **SystemVerilog Testbench** with generator, driver, monitor, and scoreboard for functional verification.
- **Scoreboard Reference Model** to compare expected vs. actual transactions.

## 🔹 Verification Flow
1. **Generator** creates randomized transactions.  
2. **Driver** applies transactions to the DUT (Design Under Test).  
3. **Monitor** observes AXI channel activity.  
4. **Scoreboard** checks correctness against the reference model.  
5. **Environment** coordinates the entire simulation.

## 📊 Results
- All test cases passed successfully.  
- Simulation logs confirm correct DMA operation with AXI4-Lite protocol.  

## 🛠 How to Run
1. Open the project in **EDA Playground**.  
2. Select **Synopsys VCS** as the simulator.  
3. Run the testbench with waveform enabled (EPWave).  
4. Observe results in the simulation log and waveform viewer.
 
