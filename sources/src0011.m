function src0011(run, fluids, mag, tFraction)
% This function sources 2-fluid drag in the presence of gravity

dTime = run.time.dTime * tFraction;

sigma_gas  = fluids(1).particleSigma;
mu_gas     = fluids(1).particleMu;
sigma_dust = fluids(2).particleSigma;
mu_dust    = fluids(2).particleMu;

cudaSource2FluidDrag(fluids, [sigma_gas, mu_gas, dia_dust, mass_dust, dTime/2]);
cudaSourceScalarPotential(fluids, run.potentialField.field, dTime, run.geometry, run.fluid(1).MINMASS, run.fluid(1).MINMASS * 0);
cudaSource2FluidDrag(fluids, [sigma_gas, mu_gas, dia_dust, mass_dust, dTime/2]);

% Take care of any parallel synchronization we need to do to remain self-consistent
for N = 1:numel(fluids);
    fluids(N).synchronizeHalos(1, [0 1 1 1 1]);
    fluids(N).synchronizeHalos(2, [0 1 1 1 1]);
    fluids(N).synchronizeHalos(3, [0 1 1 1 1]);
end

% Assert boundary conditions
for N = 1:numel(fluids)
    fluids(N).setBoundaries(1);
    fluids(N).setBoundaries(2);
    fluids(N).setBoundaries(3);
end

end