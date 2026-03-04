# Beyond NetLogo: Agent-Based Simulation of Bark Beetle Dynamics using GAMA

## Overview
This repository contains the code, data, and analytical scripts for the study **"Beyond NetLogo: Agent-based Simulation of Bark Beetle Dynamics using GAMA"**. 

The project ports an existing, data-driven NetLogo model of the European spruce bark beetle (*Ips typographus*) to the GAMA platform. It serves as a **spatial sensitivity analysis**, evaluating how the transition from an aggregated 100m grid to a high-resolution 25m spatial topology impacts simulated outbreak dynamics, source-sink connectivity, and the Allee effect in fragmented Alpine forests.

## Repository Structure
* `/models`
  * `BarkBeetle_100m.gaml` - The baseline GAMA model at 100m aggregated resolution.
  * `BarkBeetle_25m.gaml` - The high-resolution GAMA model explicitly depicting fragmented tree patches.
  * *(Note: The original NetLogo baseline model is referenced in the paper and builds upon the work of Hirschmugl et al.)*
* `/data`
  * `temperatures_pointdecimal.CSV` - Daily mean temperature driving the phenological development.
  * `gama_results_combined.csv` - Raw simulation output (Monte Carlo runs) for the 100m model.
  * `gama_results_combined25x25.csv` - Raw simulation output for the 25m spatial sensitivity analysis.
* `/analysis`
  * `plot_resolutions.py` - Python script for statistical validation (Pearson, RMSE) and generating the comparative plots used in the study.

## Requirements and Usage
### 1. Running the Simulations
To run the Agent-Based Models, download and install the [GAMA Platform](https://gama-platform.org/). Import the `/models` folder into your GAMA workspace and execute the `experiment` blocks defined in the `.gaml` files. 
*(Warning: The 25m model is computationally intensive and requires sufficient RAM allocation).*

### 2. Running the Data Analysis
The Python scripts require the following packages:
```bash
pip install pandas numpy matplotlib seaborn scipy
