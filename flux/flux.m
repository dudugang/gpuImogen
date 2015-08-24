function flux(run, mass, mom, ener, mag, order)
% This function manages the fluxing routines for the split code by managing the appropriate fluxing 
% order to try and average out any biasing caused by the Strang splitting.
%
%>< run         run manager object                                                      ImogenManager
%>< mass        mass density                                                            FluidArray
%>< mom         momentum density                                                        FluidArray(3)
%>< ener        energy density                                                          FluidArray
%>< mag         magnetic field                                                          MagnetArray(3)
%>> order       direction of flux sweep (1 forward/-1 backward)                         int     +/-1

    %-----------------------------------------------------------------------------------------------
    % Set flux direction and magnetic index components
    %-------------------------------------------------    

    p = [1 3 2; 2 1 3; 1 2 3; 2 3 1; 3 1 2; 3 2 1];

    directVec = p(mod(run.time.iteration-1,6)+1,:)';
    magneticIndices = [3 2; 3 1; 2 1];
    magneticIndices = magneticIndices(directVec,:);

    %===============================================================================================
    if (order > 0) %                             FORWARD FLUXING
    %===============================================================================================
        for n = [1 2 3]
            if (mass.gridSize(directVec(n)) < 3), continue; end

            if run.fluid.ACTIVE
                xchgIndices(run.pureHydro, mass, mom, ener, mag, directVec(n));
                relaxingFluid(run, mass, mom, ener, mag, directVec(n));
                xchgIndices(run.pureHydro, mass, mom, ener, mag, directVec(n));
                xchgFluidHalos(mass, mom, ener, directVec(n));
            end

            if run.magnet.ACTIVE
                magnetFlux(run, mass, mom, mag, directVec(n), magneticIndices(n,[1 2]));
            end

        end
    %===============================================================================================        
    else %                                       BACKWARD FLUXING
    %===============================================================================================
        for n = [3 2 1]
            if (mass.gridSize(directVec(n)) < 3), continue; end

            if run.magnet.ACTIVE
                magnetFlux(run, mass, mom, mag, directVec(n), magneticIndices(n,[2 1]));
            end

            if run.fluid.ACTIVE
                xchgIndices(run.pureHydro, mass, mom, ener, mag, directVec(n));
                relaxingFluid(run, mass, mom, ener, mag, directVec(n));
                xchgIndices(run.pureHydro, mass, mom, ener, mag, directVec(n));

                xchgFluidHalos(mass, mom, ener, directVec(n));
            end
        end
    end

end

function xchgIndices(isFluidOnly, mass, mom, ener, mag, toex)

s = { mass, ener, mom(1), mom(2), mom(3) };

for i = 1:5
    s{i}.arrayIndexExchange(toex, 1);
    s{i}.store.arrayIndexExchange(toex, 0);
end

if isFluidOnly == 0
    s = {mag(1).cellMag, mag(2).cellMag, mag(3).cellMag};
    for i = 1:3
        s{i}.arrayIndexExchange(toex, 1);
    end
end

end

function xchgFluidHalos(mass, mom, ener, dir)
s = { mass, ener, mom(1), mom(2), mom(3) };

GIS = GlobalIndexSemantics();

for j = 1:5;
  cudaHaloExchange(s{j}, [1 2 3], dir, GIS.topology, s{j}.bcHaloShare);
end

end

