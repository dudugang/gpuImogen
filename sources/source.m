function source(run, mass, mom, ener, mag)
% This function sources the non-conservative terms in the MHD equations like gravitational potential
% and radiation terms. Effectively it provides the means to add terms that cannot be brought within 
% the del operator, which is the foundation of the spatial fluxing routines.
%
%>< run			data manager object.                                            ImogenManager
%>< mass		mass density                                                    FluidArray  
%>< mom			momentum density                                                FluidArray(3)
%>< ener        energy density                                                  FluidArray
%>< mag         magnetic field density                                          FluidArray(3)

    %--- External scalar potential (e.g. non self gravitating component) ---%
    if run.potentialField.ACTIVE
        cudaApplyScalarPotential(mass.gputag, ener.gputag, mom(1).gputag, mom(2).gputag, mom(3).gputag, run.potentialField.field.GPU_MemPtr, run.time.dTime, [run.DGRID{1} run.DGRID{2} run.DGRID{3}], run.fluid.MINMASS*20);
    end

    %--- Gravitational Potential Sourcing ---%
    %       If the gravitational portion of the code is active, the gravitational potential terms
    %       in both the momentum and energy equations must be appended as source terms.
    if run.selfGravity.ACTIVE
        enerSource = zeros(run.gridSize);
        for i=1:3
            momSource       = run.time.dTime*mass.thresholdArray ...
                                                    .* grav.calculate5PtDerivative(i,run.DGRID{i});
            enerSource      = enerSource + momSource .* mom(i).array ./ mass.array;
            mom(i).array    = mom(i).array - momSource;
        end
        ener.array          = ener.array - enerSource;
    end
    
    %--- Radiation Sourcing ---%
    %       If radiation is active, the radiation terms are subtracted, as a sink, from the energy
    %       equation.
    if run.fluid.radiation.type ~= ENUM.RADIATION_NONE
        ener.array              = ener.array - run.time.dTime*run.fluid.radiation.solve(run, mass, mom, ener, mag);
    end
    
end
