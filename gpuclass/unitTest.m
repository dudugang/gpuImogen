function result = unitTest(n2d, max2d, n3d, max3d, funcList)

result = 0;

if(nargin == 2)
    funcList = max2d;
    specificRez = 1;
    SaveManager.logPrint('Running one test using resolution: %i\n', int32(n2d));
else

if(nargin < 4)
    disp('unitTest help:');
    disp('unitTest(n2d, max2d, n3d, max3d, funcList):');
    disp('    n2d:   Number of 2 dimensional resolutions to fuzz functions with');
    disp('    max2d: Maximum resolution to use for 2D tests');
    disp('    n3d:   Number of 3 dimensional resolutions to fuzz functions with');
    disp('    max3d: Maximum resolution to use for 3D tests');
    disp('    funcList: {''strings'', ''naming'', ''functions''} or blank to test all.');
    return;
end

    specificRez = 0;

end

if(nargin == 4)
    funcList = { 'cudaArrayAtomic', 'cudaArrayRotateB', 'freezeAndPtot', 'cudaFwdAverage', 'cudaFwdDifference', 'freezeAndPtot'};
end

nFuncs = numel(funcList);

if specificRez
    D = -1;
    R = n2d;
else
    D = [2*ones(n2d,1); 3*ones(n3d,1)];
    R = [ones(n2d,1)*max2d; ones(n3d,1)*max3d];
end

tic;
for F = 1:nFuncs
    outcome = iterateOnFunction(funcList{F}, D, R);

    switch outcome
        case 1;  SaveManager.logPrint('Tests of %s failed!\n', funcList{F}); result = 1;
        case 0;  SaveManager.logPrint('Tests of %s successful!\n', funcList{F});
        case -1; SaveManager.logPrint('Test for function named %s not implemented\n', funcList{F});
        case -2; SaveManager.logPrint('No function named %s...\n', funcList{F});
    end

end

if mpi_amirank0(); fprintf('### Tested %i functions in %fsec ###\n', nFuncs, toc); end
end

function targfunc = name2func(func)
    targfunc = @noSuchThing; % Default to failure
    if strcmp(func, 'cudaArrayAtomic'); targfunc = @testCudaArrayAtomic; end
    if strcmp(func, 'cudaArrayRotateB'); targfunc = @testCudaArrayRotateB; end
    if strcmp(func, 'cudaFreeRadiation'); targfunc = @testCudaFreeRadiation; end
    if strcmp(func, 'cudaFwdAverage'); targfunc = @testCudaFwdAverage; end
    if strcmp(func, 'cudaFwdDifference'); targfunc = @testCudaFwdDifference; end
    if strcmp(func, 'cudaMHDKernels'); targfunc = @testCudaMHDKernels; end
    if strcmp(func, 'cudaMagPrep'); targfunc = @testCudaMagPrep; end
    if strcmp(func, 'cudaMagTVD'); targfunc = @testCudaMagTVD; end
    if strcmp(func, 'cudaMagW'); targfunc = @testCudaMagW; end
    if strcmp(func, 'cudaShift'); targfunc = @testCudaShift; end
    if strcmp(func, 'cudaSoundspeed'); targfunc = @testCudaSoundspeed; end
    if strcmp(func, 'cudaSourceAntimach'); targfunc = @testCudaSourceAntimach; end
    if strcmp(func, 'cudaSourceRotatingFrame'); targfunc = @testCudaSourceRotatingFrame; end
    if strcmp(func, 'cudaSourceScalarPotential'); targfunc = @testCudaSourceScalarPotential; end
    if strcmp(func, 'cudaStatics'); targfunc = @testCudaStatics; end
    if strcmp(func, 'directionalMaxFinder'); targfunc = @testDirectionalMaxFinder; end
    if strcmp(func, 'freezeAndPtot'); targfunc = @testFreezeAndPtot; end
end


function outcome = iterateOnFunction(fname, D, R)
    outcome = 0;
    for n = 1:numel(D)
        res = randomResolution(D(n), R(n,:));
        func = name2func(fname);
        outcome = func(res);
        if mpi_any(outcome ~= 0)
            if outcome ~= 0; fprintf('RANK %i: Copypasta to rerun this exact test:\n\tunitTest([%i %i %i], {''%s''})\n', mpi_myrank(), int32(res(1)), int32(res(2)), int32(res(3)), fname); end
            outcome = mpi_max(outcome);
            break;
        end
        SaveManager.logPrint('.');
    end
end

function R = randomResolution(dim, nmax)
    if dim == -1 % Runs a specific resolution
        R = nmax;
    else
        x = GPUManager.getInstance();
        nMin = max(3*numel(x.deviceList), 6);
        R = round(nmax.*rand(1,3));
        R(R < nMin) = nMin;
        if dim < 3; R(3) = 1; end
    end
end

% Provide a default 'return does-not-exist' target
function failure = noSuchThing(res); failure = -1; end

function outcome = testCudaArrayAtomic(res)
    r = mpi_myrank();
    fail = 0;
    X = rand(res);
    Xg = GPU_Type(X);

    cudaArrayAtomic(Xg, .4, 1);
    X(X < .4) = .4;
    if any(Xg.array(:) ~= X(:) ); fprintf('  !!! RANK %I: Test failed: setting min, res=%ix%ix%i\n', r, res(1),res(2), res(3) ); fail = 1; end

    cudaArrayAtomic(Xg, .6, 2);
    X(X > .6) = .6;
    if any(Xg.array(:) ~= X(:) ); fprintf('  !!! RANK %I: Test failed: setting max, res=%ix%ix%i\n', r, res(1),res(2), res(3) ); fail = 1; end
  
    X( (X > .4) & (X < .6) ) = NaN;
    Xg.array = X;
    X(isnan(X)) = 0;
    cudaArrayAtomic(Xg, 0, 3);
    if any(Xg.array(:) ~= X(:) ); fprintf('  !!! RANK %i: Test failed: removing NaN, res=%ix%ix%i\n', r, res(1),res(2), res(3) ); fail = 1; end

    outcome = fail;
end

function fail = testCudaArrayRotateB(res)
    fail = 0;
    r = mpi_myrank();
    X = rand(res);
    Xg = GPU_Type(X);
    Yg = GPU_Type(cudaArrayRotateB(Xg,2));
    Yg.array(1);
    Xp = permute(X, [2 1 3]);
    if any(any(any(Yg.array ~= Xp)));  fprintf('  !!! RANK %i: Test failed: XY transpose !!!', r); fail = 1; end
    clear Yg;

    if res(3) > 3 % Test further transpositions in higher dimensions
        Yg = GPU_Type(cudaArrayRotateB(Xg,3));
        Xp = permute(X, [3 2 1]);

        if any(any(any(Yg.array ~= Xp))); fprintf('   !!! RANK %i: Test failed: XZ transpose !!!', r); fail = 1; end

        Zg = GPU_Type(cudaArrayRotateB(Xg, 4));
        Xp = permute(X, [1 3 2]);
        if any(any(any(Zg.array ~= Xp))); fprintf('   !!! RANK %i: Test failed: YZ transpose !!!', r); fail = 1; end
        
        Zg = cudaArrayRotateB(Xg, 5);
        cudaArrayRotateB(Zg,5);
        cudaArrayRotateB(Zg,5);
        if any(any(any(GPU_download(Zg) ~= X))); fprintf('   !!! RANK %i: Test failed: Permute indices left !!!', r); fail = 1; end 
        GPU_free(Zg);

        Zg = cudaArrayRotateB(Xg, 6);
        cudaArrayRotateB(Zg,6);
        cudaArrayRotateB(Zg,6);
        if any(any(any(GPU_download(Zg) ~= X))); fprintf('   !!! RANK %i: Test failed: Permute indices right !!!', r); fail = 1; end 
        GPU_free(Zg);

     end

end

function fail = testCudaFreeRadiation(res)
    fail = 0;
    rho = 2 - 1.8*rand(res);
    px = 2*rand(res);
    py = 3*rand(res);
    pz = 2*rand(res);
    bx = rand(res);   bxd = GPU_Type(bx);
    by = rand(res);   byd = GPU_Type(by);
    bz = rand(res);   bzd = GPU_Type(bz); % The del.b constraint doesn't matter, this just calculates |B|^2 to subtract it

    T = .5*(px.^2+py.^2+pz.^2) ./ rho;
    B = .5*(bx.^2+by.^2+bz.^2);

    Ehydro = T + .5+.25*rand(res); %Ehydrod = GPU_Type(Ehydro);
    Emhd = Ehydro + B;             %Emhdd = GPU_Type(Emhd);

    for thtest = [-.3 0 .28 .5 1 1.3]
        gm1 = 2/3;
        Tmin = 0.2;

        %Ehydrod = GPU_Type(Ehydro); % Reload internal energy array
        
        FM = FluidManager();
        FM.DEBUG_uploadData(rho, Ehydro, px, py, pz);
        
        % RADIATION RATE -- HYDRODYNAMIC
        rtest = GPU_Type(cudaFreeRadiation(FM, bxd, byd, bzd, [5/3 thtest 1 0 1]));
        rtrue = (rho.^(2-thtest)) .* (gm1*(Ehydro-T)).^(thtest);

        if max(abs(rtrue(:)-rtest.array(:))) > 1e-12
            fail = 1;
            fprintf('    !!! RANK %i: Failed calculating radiation rate in hydrodynamic gas. Theta: %f\n', mpi_myrank(), thtest);
        end

        tau = .1*.5/max(rtest.array(:));

        % RADIATION LOSS -- HYDRODYNAMIC
        cudaFreeRadiation(FM, bxd, byd, bzd, [5/3 thtest tau Tmin 1]);
        P0 = gm1*(Ehydro - T);

        % Apply the various algorithms here
        if thtest == 0
            % Radiation rate is independent of pressure:
            Pf = P0 - gm1 * tau * rho.^2;
        elseif thtest == 1
            Pf = exp(log(P0) - gm1*tau*rho);
        else
            beta = gm1*(thtest-1)*tau*rho.^(2-thtest);
            Pf = (P0.^(1-thtest)) + beta;
            Pf(Pf > 0) = Pf(Pf > 0).^(1/(1-thtest));
        end
       
        COLD = (P0 < Tmin*rho);
        COOL = (Pf < Tmin*rho);

        Pf(COOL) = Tmin*rho(COOL);
        Pf(COLD) = P0(COLD);
        Enew = T + Pf/gm1;

        if max(abs(Enew(:) - FM.ener.array(:))) > 1e-12
            fail = 1;
            fprintf('   !!! RANK %i: Failed calculating radiation loss in hydrodynamic gas. Theta: %f\n', mpi_myrank(), thtest);
        end
        clear FM;

        FM = FluidManager();
        FM.DEBUG_uploadData(rho, Emhd, px, py, pz);

        % RADIATION RATE -- MAGNETOHYDRODYNAMIC
        rtest = GPU_Type(cudaFreeRadiation(FM, bxd, byd, bzd, [5/3 thtest 1 0 0]));
        rtrue = (rho.^(2-thtest)) .* (gm1*(Emhd-T-B)).^(thtest);

        if max(abs(rtrue(:)-rtest.array(:))) > 1e-12
            fail = 1;
            fprintf('   !!! RANK %i: Failed calculating radiation rate in MHD gas. Theta: %f\n', mpi_myrank(), thtest);
        end

        % RADIATION LOSS -- MAGNETOHYDRODYNAMIC
        tau = .01*.5/max(rtest.array(:));

        cudaFreeRadiation(FM, bxd, byd, bzd, [5/3 thtest tau Tmin 0]);
        P0 = gm1*(Emhd - T - B);

        % Apply the various algorithms here
        if thtest == 0
            % Radiation rate is independent of pressure:
            Pf = P0 - gm1 * tau * rho.^2;
        elseif thtest == 1
            Pf = exp(log(P0) - gm1*tau*rho);
        else
            beta = gm1*(thtest-1)*tau*rho.^(2-thtest);
            Pf = (P0.^(1-thtest)) + beta;
            Pf(Pf > 0) = Pf(Pf > 0).^(1/(1-thtest));
        end

        COLD = (P0 < Tmin*rho);
        COOL = (Pf < Tmin*rho);

        Pf(COOL) = Tmin*rho(COOL);
        Pf(COLD) = P0(COLD);

        Enew = T + B + Pf/gm1;

        if max(abs(Enew(:) - FM.ener.array(:))) > 1e-12
                fail = 1;
                fprintf('   !!! RANK %i: Failed calculating radiation loss in MHD gas. Theta: %i\n', mpi_myrank(), thtest);
        end
        clear FM;
    end

end

function fail = testCudaFwdAverage(res)
F = rand(res);

xi = 1:1:res(1);
yi = 1:1:res(2);
zi = 1:1:res(3);
    
G1 = .5*F(xi, yi, zi) + .5*F(circshift(xi',[-1,0,0]), yi, zi);
G2 = .5*F(xi, yi, zi) + .5*F(xi, circshift(yi',[-1,0,0]), zi);
G3 = .5*F(xi, yi, zi) + .5*F(xi, yi, circshift(zi',[-1,0,0]));

%GPU 

FD = GPU_Type(F);
G1D = GPU_Type(cudaFwdAverage(FD, 1));
G2D = GPU_Type(cudaFwdAverage(FD, 2));
G3D = GPU_Type(cudaFwdAverage(FD, 3));

a = max(G1(:)-G1D.array(:));
b = max(G2(:)-G2D.array(:));
c = max(G3(:)-G3D.array(:));
n = [a,b,c];

if max(abs(n)) < 1e-14
    fail = 0;
else; fail = 1;
end
end

function fail = testCudaFwdDifference(res)
lambda = 0.1; %could be any real number
R = rand(res);
F = rand(res);

xi = 1:1:res(1);
yi = 1:1:res(2);
zi = 1:1:res(3);

delta_x = F(xi, yi, zi) - F(circshift(xi',[-1,0,0]), yi, zi);
delta_y = F(xi, yi, zi) - F(xi, circshift(yi',[-1,0,0]), zi);
delta_z = F(xi, yi, zi) - F(xi, yi, circshift(zi',[-1,0,0]));

Rx = R-lambda*(delta_x);
Ry = R-lambda*(delta_y);
Rz = R-lambda*(delta_z);

%GPU

RD = GPU_Type(R);
FD = GPU_Type(F);

cudaFwdDifference(RD,FD,1,lambda);
a = max(Rx(:)-RD.array(:));
RD.array = R;
cudaFwdDifference(RD,FD,2,lambda);
b = max(Ry(:)-RD.array(:));
RD.array = R;
cudaFwdDifference(RD,FD,3,lambda);
c = max(Rz(:)-RD.array(:));

n = [a,b,c];

if max(abs(n)) < 1e-14
    fail = 0;
else; fail = 1;
end
end

function fail = testCudaMHDKernels(res)
fail = -1;
%hmmmmm... nope, barely have time to write unit tests for code that actually runs, not writing for
%dead crap...
end

function fail = testCudaMagPrep(res)
fail = -1;

rho = 2 - rand(res);
p = rand(res);

x = 1:1:res(1);
i = 1:1:res(2);

rhoD = GPU_Type(rho);
pD = GPU_Type(p);
cudaMagPrepD = GPU_Type(cudaMagPrep(pD, rhoD, [i x]));

Adir = [1 0 0; 1 0 0; 0 1 0; 0 1 0; 0 0 1; 0 0 1];
Bdir = [0 1 0; 0 0 1; 1 0 0; 0 0 1; 1 0 0; 0 1 0];

CudaDir = [1 2; 1 3; 2 1; 2 3; 3 1; 3 2];

for N = 1:6
    a1 = .25*(circshift(p, Adir(N,:)) + circshift(p, Adir(N,:)*0)) ./ (circshift(rho, Adir(N,:)) + circshift(rho, Adir(N,:)*0));
    a2 = (circshift(a1, Bdir(N,:)) + 2*a1 + circshift(a1, -Bdir(N,:)));
    cudaMagPrepD = GPU_Type(cudaMagPrep(pD, rhoD, [CudaDir(N, :)]));
    a(N) = max(a2(:) - cudaMagPrepD.array(:));
end

n = [a(1), a(2), a(3), a(4), a(5), a(6)];
abs(n)

if abs(n) < 1e-12
    fail = 0;
else; fail = -1;
end
end

function fail = testCudaMagTVD(res)
fail = -1;
%no
end

function fail = testCudaMagW(res)
fail = -1;
%no
end

function fail = testCudaPointPotentials(res)
fail = -1;
%later
end

function fail = testCudaShift(res)
fail = -1;
%not used!!!!!!! but there should be a function in /gpuclass
%(kirk_testCudaShift) which implements this routine, if needed
end

function fail = testCudaSoundspeed(res)

gamma = 5/3; %choose a number between 1 and 5/3
rho =  2 - rand(res);
bx = 0.1*rand(res);
by = 0*rand(res);
bz = 0*rand(res);
px = 2*rand(res);
py = 3*rand(res);
pz = 2*rand(res);

B = (bx.^2+by.^2+bz.^2);
T = .5*(px.^2+py.^2+pz.^2) ./ rho;
Etotal1 = T + .1 + rand(res);
Etotal0 = Etotal1 + 0.5*B; %for no B field, .1 could be any small number
P = (gamma-1)*(Etotal1 - T);

c_sq = sqrt(gamma*P./rho); %sound speed c_s^2
cf_sq = sqrt(B./rho); %alven speed c_a^2
c_fast = sqrt((c_sq).^2 + (cf_sq).^2); %c_fast^2

%GPU

rhoD =  GPU_Type(rho);
bxD = GPU_Type(bx);
byD = GPU_Type(by);
bzD = GPU_Type(bz);
pxD = GPU_Type(px);
pyD = GPU_Type(py);
pzD = GPU_Type(pz);
Etotal0D = GPU_Type(Etotal0);
Etotal1D = GPU_Type(Etotal1);

c_s = GPU_Type(cudaSoundspeed(rhoD, Etotal0D, pxD, pyD, pzD, bxD, byD, bzD, gamma));
c_s1 = GPU_Type(cudaSoundspeed(rhoD, Etotal1D, pxD, pyD, pzD, gamma));

a = max(abs(c_sq(:) - c_s1.array(:)));
b = max(abs(c_fast(:) - c_s.array(:)));
n = [a,b];

if max(abs(n)) < 1e-10
    fail = 0;
else; fail = 1;
end
end

function fail = testCudaSourceAntimach(res)
fail = -1;
%no
end

function fail = testCudaSourceRotatingFrame(res)

w = rand(1);
px = rand(res);
py = rand(res);
pz = rand(res);
x = 1:res(1);
y = 1:res(2);
z = 1:res(3);
rho = 0.5 + rand(res);
vx = px ./ rho;
vy = py ./ rho;
E = rand(res) + .5 * rho .* ((vx).^2 + (vy).^2);
[x,y] = ndgrid(x,y,z);
dt = .01;

FM = FluidManager();
FM.DEBUG_uploadData(rho, E, px, py, pz);

%dvx = (2 * w * vy + w^2 * x)*(dt/2);
%dvy = (-2 * w * vx + w^2 * y)*(dt/2);

dpx = (2 * w * py + w^2 * rho .* x)*(dt/2);
dpy = (-2 * w * px + w^2 * rho .* y)*(dt/2);

%vx1 = vx + dvx;
%vy1 = vy + dvy;

px1 = px + dpx;
py1 = py + dpy;

%dvx1 = (2 * w * vy1 + w^2 * x)*(dt);
%dvy1 = (-2 * w * vx1 + w^2 * y)*(dt);
 
dpx1 = (2 * w * py1 + w^2 * rho .* x)*(dt);
dpy1 = (-2 * w * px1 + w^2 * rho .* y)*(dt);

%vx = vx + dvx1;
%vy = vy + dvy1;

E = E + (px + .5*dpx1) .* (dpx1 ./ rho) + (py + .5*dpy1) .* (dpy1 ./ rho);

px = px + dpx1;
py = py + dpy1;

%GPU
% Make the GPU uploader partition the X-Y vectors correctly
gm = GPUManager.getInstance();
gm.pushParameters();
gm.partitionDir = 1;
cudaSourceRotatingFrame(FM, w, dt, GPU_Type([1:res(1) 1:res(2)], 1));
gm.popParameters();

a = max(px(:) - FM.mom(1).array(:));
b = max(py(:) - FM.mom(2).array(:));
c = max(E(:) - FM.ener.array(:));

n = [a, b, c];
if max(abs(n)) < 1e-10
    fail = 0;
else; fail = 1;
end
end

function fail = testCudaSourceScalarPotential(res)
% FIXME: this probably breaks in parallel?

GM = GeometryManager(res);
GM.makeBoxSize(.01*res);

rho = rand(res);
px = rand(res);
py = rand(res);
pz = rand(res);
E = rand(1) + .5*(px.^2 + py.^2 +pz.^2) ./ rho;
phi = rand(res);

FM = FluidManager();
FM.DEBUG_uploadData(rho, E, px, py, pz);

beta = ones(res);
dt = .01; % small timestep
d3x = [.01, .01, .01]; % small volume
rho_nograv = .01; % density for min effect of grav
rho_fullgrav = .1; % density for full effect of grav

FM.MINMASS = rho_nograv;

phiD = GPU_Type(phi);

beta(rho_fullgrav < rho) = 1;
beta(rho < rho_fullgrav) = (rho(rho < rho_fullgrav) - rho_nograv) / (rho_fullgrav - rho_nograv);
beta(rho < rho_nograv) = 0;

grad_phiX = .5*(circshift(phi, [-1,0,0]) - circshift(phi, [1,0,0])) / d3x(1);
grad_phiY = .5*(circshift(phi, [0,-1,0]) - circshift(phi, [0,1,0])) / d3x(2);
grad_phiZ = .5*(circshift(phi, [0,0,-1]) - circshift(phi, [0,0,1])) / d3x(3);

Fx = -beta .* rho .* grad_phiX;
Fy = -beta .* rho .* grad_phiY;
Fz = -beta .* rho .* grad_phiZ;

%e0 = E; px0 = px; py0 = py;
E = E - beta .* (px .* grad_phiX + py .* grad_phiY + pz .* grad_phiZ)*dt ...
      + .5*rho.*beta.*beta.*(grad_phiX.^2+grad_phiY.^2+grad_phiZ.^2)*dt*dt;
px = px + Fx * dt;
py = py + Fy * dt;
pz = pz + Fz * dt;


cudaSourceScalarPotential(FM, phiD, GM, [dt, rho_nograv, rho_fullgrav]);
a = max(px(:) - FM.mom(1).array(:));
b = max(py(:) - FM.mom(2).array(:));
c = max(pz(:) - FM.mom(3).array(:));
d = max(E(:) - FM.ener.array(:));

n = [a, b, c, d];
if max(abs(n)) < 1e-10
    fail = 0;
else; fail = 1;
end
end

function fail = testCudaStatics(res)
fail = -1;
%next
end

function fail = testDirectionalMaxFinder(res)
fail = 0;

% test one: simple max
rho = .5 + rand(res);
rhoD = GPU_Type(rho);

cpuResult = mpi_max(max(rho(:)));
gpuResult = mpi_max(directionalMaxFinder(rhoD));

if cpuResult ~= gpuResult 
    fprintf('    !!! RANK %i: Simple global maximum was not correct!!! cpu=%f, gpu=%f\n', mpi_myrank(), cpuResult, gpuResult);
    fail = 1;
end

% Test two: CFL speed determination
% Make up some other crap
cs = 1 + rand(res); csD = GPU_Type(cs);
px = -.5 + rand(res); pxD = GPU_Type(px);
py = -.5 + rand(res); pyD = GPU_Type(py);
pz = -.5 + rand(res); pzD = GPU_Type(pz);

% Use it to compute the CFL constraint speed
cflDir = 1;
cflX = max(cs(:) + abs(px(:) ./ rho(:)));
cfl = cflX;

cflY = max(cs(:) + abs(py(:) ./ rho(:)));
if cflY > cfl; cfl = cflY; cflDir = 2; end

cflZ = max(cs(:) + abs(pz(:) ./ rho(:)));
if cflZ > cfl; cfl = cflZ; cflDir = 3; end

cfl = mpi_max(cfl);

% Now make the GPU compute it
[gpuCFL, gpuDIR] = directionalMaxFinder(rhoD, csD, pxD, pyD, pzD);

gpuCFL = mpi_max(gpuCFL);

if gpuCFL ~= cfl
    fprintf('   !!! RANK %i: Test failed to return correct cfl speed !!! cpu=%f, gpu=%f\n', mpi_myrank(), cfl, gpuCFL);
    fail = 1;
end
% FIXME this requires the complex-structs thing in MPI
if gpuDIR ~= cflDir
    fprintf('   !!! RANK %i: Test failed to return correct cfl direction !!! cpu=%i, gpu=%i\n', mpi_myrank(), int32(cflDir), int32(gpuDIR));
    fail = 1;
end

% Test 3:
% c = directionalMaxFinder(a1, a2, direct) will find the max of |a1(r)+a2(r)| in the
%      'direct' direction (1=X, 2=Y, 3=Z)
% This is used by the xin/jin algorithm to find the freezing speed
% This code branch is terrible and should not be used
% I am 90% sure the current xin/jin kernel doesn't even use this call

end

function fail = testFreezeAndPtot(res)
    %[xpos, ypos, zpos] = ndgrid((1:res(1))*2*pi/res(1), (1:res(2))*2*pi/res(2), (1:res(3))*2*pi/res(3));
    % Generate nontrivial conditions
    rho = ones(res);
    px = zeros(res);% + sin(xpos);
    py = ones(res);% + sin(ypos + zpos);
    pz = zeros(res);%cos(zpos);
    E  = .5*(px.^2+py.^2+pz.^2)./rho + 2;% + .3*cos(4*xpos) + .1*sin(3*ypos);
    Bx = zeros(res);
    By = zeros(res);
    Bz = zeros(res);

    ptot = (2/3)*(E - .5*(px.^2+py.^2+pz.^2)./rho);
    freeze = max(sqrt((5/3)*ptot./rho) + abs(px./rho),[], 1);

    % Translate to GPU vars
    rhoD = GPU_Type(rho);
    pxD = GPU_Type(px); pyD = GPU_Type(py); pzD = GPU_Type(pz);
    ED = GPU_Type(E);
    BxD = GPU_Type(Bx); ByD = GPU_Type(By); BzD = GPU_Type(Bz);

    % Call GPU routine
    geo = GeometryManager(res);
    [pdev, cdev] = freezeAndPtot(rhoD, ED, pxD, pyD, pzD, BxD, ByD, BzD, 5/3, 1, .01, geo.topology);

    pd = GPU_Type(pdev);
    cf = GPU_Type(cdev);

%[cf.array(:) freeze(:) (cf.array(:) - freeze(:))]
    fail = 0;
    if max(max(max(abs(pd.array - ptot)))) > 1e-10;  disp('   !!! Test failed: P !!!'); fail = 1; end
    if max(max(abs(cf.array(1,:,:) - freeze))) > 1e-10; disp('   !!! Test failed: C_f !!!'); fail = 1; 
end

end

