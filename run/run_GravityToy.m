

%--- Initialize test ---%
%        The number of X cells is the controlling variable in grid step size.
run                 = GravityTestInitializer([250 150 150]);
run.iterMax         = 100;

%run.rhoSphere;
%run.rhoBG;
%rho.enerSphere
run.gravity.constant    = 1;

run.image.interval      = 1;
run.image.mass          = true;
run.image.speed         = true;
run.image.momX          = true;
run.image.momY          = true;
run.image.grav          = true;
run.image.ener          = true;

run.activeSlices.xy     = true;
run.activeSlices.yz     = false;
run.activeSlices.xz     = false;
run.activeSlices.xyz         = true;

run.ppSave.dim3 = 5; % every 10 steps
%run.ppSave.dim2 = 10;

run.info            = 'Toy gravity problem test';
run.notes           = '';

% lol broken
run.gravity.solver = 'biconj';
run.gravity.tolerance = 1e-10;
run.gravity.iterMax = 150;

%--- Run tests ---%
if (true)
    IC = run.saveInitialCondsToFile();
    outpath = imogen(IC);
end

