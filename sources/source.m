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

GIS = GlobalIndexSemantics();

    %--- External scalar potential (e.g. non self gravitating component) ---%
%    if run.potentialField.ACTIVE
%        cudaSourceScalarPotential(mass.gputag, ener.gputag, mom(1).gputag, mom(2).gputag, mom(3).gputag, run.potentialField.field.GPU_MemPtr, run.time.dTime, [run.DGRID{1} run.DGRID{2} run.DGRID{3}], run.fluid.MINMASS, run.fluid.MINMASS*ENUM.GRAV_FEELGRAV_COEFF);
%    end

    % TESTING: uncomment to enable rotating frame.
    if run.frameRotateOmega ~= 0
        [xg yg] = GIS.ndgridVecs;
        xg = GPU_Type(run.DGRID{1}*(xg-run.frameRotateCenter(1)));
        yg = GPU_Type(run.DGRID{2}*(yg-run.frameRotateCenter(2)));
        cudaSourceRotatingFrame(mass.gputag, ener.gputag, mom(1).gputag, mom(2).gputag, run.frameRotateOmega, .5*run.time.dTime, xg.GPU_MemPtr, yg.GPU_MemPtr);
    end

    for n = 1:numel(run.selfGravity.compactObjects)
        % Applies gravitational sourcing from all compact objects to my domain,
        % And performs a simple accretion action if any part of their zone is in my domain.
        % Need to track star's
        % position (3D), momentum (3D), angular momentum (3D), mass (1D), radius (1D), vaccum_rho(1D), grav_rho(1D), vacccum_E(1D) = 14 doubles
        % Store [X Y Z R Px Py Pz Lx Ly Lz M rhoV rhoG EV] in full state vector:
        lowleft = GIS.cornerIndices();
        run.selfGravity.compactObjects{n}.incrementDelta( cudaAccretingStar(mass.gputag, mom(1).gputag, mom(2).gputag, mom(3).gputag, ener.gputag, run.selfGravity.compactObjects{n}.stateVector, lowleft, run.DGRID{1}, run.time.dTime, GIS.topology.nproc) );
    end

    if run.frameRotateOmega ~= 0
        cudaSourceRotatingFrame(mass.gputag, ener.gputag, mom(1).gputag, mom(2).gputag, run.frameRotateOmega, .5*run.time.dTime, xg.GPU_MemPtr, yg.GPU_MemPtr);
        clear xg
        clear yg;
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
    if strcmp(run.fluid.radiation.type, ENUM.RADIATION_NONE) == false
        run.fluid.radiation.solve(run, mass, mom, ener, mag);
    end

    if run.selfGravity.ACTIVE % | run.potentialField.ACTIVE
        % Oh you better believe we need to synchronize up in dis house
        GIS = GlobalIndexSemantics();
%        S = {mom(1), mom(2), mom(3), ener};
        for j = 1:4; for dir = 1:3
%            iscirc = double([strcmp(S{j}.bcModes{1,dir},ENUM.BCMODE_CIRCULAR) strcmp(S{j}.bcModes{2,dir}, ENUM.BCMODE_CIRCULAR)]);
            cudaHaloExchange(S{j}.gputag, [1 2 3], dir, GIS.topology, GIS.edgeInterior(:,dir));
        end; end
    end

mass.applyStatics();
ener.applyStatics();
mom(1).applyStatics();
mom(2).applyStatics();
mom(3).applyStatics();
    
end
