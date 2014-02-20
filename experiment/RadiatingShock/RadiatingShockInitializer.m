classdef RadiatingShockInitializer < Initializer
% Creates initial conditions for the corrugation instability shock wave problem. The fundamental 
% conditions are two separate regions. On one side (1:midpoint) is in inflow region of accreting
% matter that is low mass density with high momentum. On the other side is a high mass density
% and low momentum region representing the start. The shockwave is, therefore, the surface of the
% star. This problem assumes a polytropic equation of state where the polytropic constant, K, is
% assumed to be 1 on both sides of the shock.
%
% Unique properties for this initializer:
%   perturbationType    enumerated type of perturbation used to seed.                   str
%   seedAmplitude       maximum amplitude of the seed noise values.                     double
%   theta               Angle between pre and post shock flows.                         double
%   sonicMach           Mach value for the preshock region.                             double
%   alfvenMach          Magnetic mach for the preshock region.                          double
        
%===================================================================================================
    properties (Constant = true, Transient = true) %                            C O N S T A N T  [P]
        RANDOM          = 'random';
        COSINE          = 'cosine';
        COSINE_2D       = 'cosine_2d';
    end%CONSTANT
    
%===================================================================================================
    properties (SetAccess = public, GetAccess = public) %                           P U B L I C  [P]
        perturbationType;   % Enumerated type of perturbation used to seed.             str
        seedAmplitude;      % Maximum amplitude of the seed noise values.               double
        cos2DFrequency;     % Resolution independent frequency for the cosine 2D        double
                            %   perturbations in both y and z.
        randomSeed_spectrumLimit; % Max ky/kz mode# seeded by a random perturbation

        theta;
        sonicMach;

        radBeta;            % Radiation rate = radBeta P^radTheta rho^(2-radTheta)
        radTheta; 

        fractionPreshock;   % The fraction of the grid to give to preshock cells; [0, 1)
        fractionTillSingularity; % The fraction of the distance to the singularity the postshock grid is to cover; [0, 1)
                            % Thus we have [nx*f = preshock | nx*(1-f) = postshock] with hx = len_singularity * f_t / (nx*(1-f));
    end %PUBLIC

%===================================================================================================
    properties (Dependent = true) %                                            D E P E N D E N T [P]
    end %DEPENDENT
    
%===================================================================================================
    properties (SetAccess = protected, GetAccess = protected) %                P R O T E C T E D [P]
        mass;               % pre and post shock mass density values.                   double(2)
        velocity;           % pre and post shock momentum density values.               double(3,2)
        pressure;           % pre and post shock pressure density values.               double(2)
    end %PROTECTED
    
%===================================================================================================
    methods %                                                                     G E T / S E T  [M]
        
%___________________________________________________________________________________________________ CorrugationShockInitializer
% Creates an Iiitializer for corrugation shock simulations. Takes a single input argument that is
% either the size of the grid, e.g. [300, 6, 6], or the full path to an existing results data file
% to use in loading
        function obj = HydroShockInitializer(input)
            obj                  = obj@Initializer();
            obj.gamma            = 5/3;
            obj.runCode          = 'RADHD';
            obj.info             = 'Radiating HD shock';
            obj.fractionPreshock = .25;
            obj.fractionTillSingularity = .95;
            obj.mode.fluid       = true;
            obj.mode.magnet      = false;
            obj.mode.gravity     = false;
            obj.treadmill        = false;
            obj.cfl              = 0.35;
            obj.iterMax          = 10;
            obj.bcMode.x         = ENUM.BCMODE_CONST;
            obj.bcMode.y         = ENUM.BCMODE_CIRCULAR;
            obj.bcMode.z         = ENUM.BCMODE_CIRCULAR;
            obj.bcInfinity       = 20;
            obj.activeSlices.xy  = true;
            obj.activeSlices.xyz = true;
            obj.ppSave.dim2      = 5;
            obj.ppSave.dim3      = 25;
            obj.image.mass       = true;
            obj.image.interval   = 10;

%            obj.dGrid.x.points   = [0, 5;    33.3, 1;    66.6, 1;    100, 5];
            
            obj.perturbationType = HydroShockInitializer.RANDOM;
            obj.randomSeed_spectrumLimit = 64; % 
            obj.seedAmplitude    = 5e-4;
            
            obj.theta            = 0;
            obj.sonicMach        = 3;

            obj.radTheta = .5;
            obj.radBeta = 1;
            
            obj.logProperties    = [obj.logProperties, 'gamma'];

            obj.operateOnInput(input, [300, 6, 6]);
            obj.pureHydro = 1;
        end

    end%GET/SET
    
%===================================================================================================
    methods (Access = public) %                                                     P U B L I C  [M]
        
    end%PUBLIC
    
%===================================================================================================    
    methods (Access = protected) %                                          P R O T E C T E D    [M]
        
%___________________________________________________________________________________________________ calculateInitialConditions
        function [mass, mom, ener, mag, statics, potentialField, selfGravity] = calculateInitialConditions(obj)
        % Returns the initial conditions for a corrugation shock wave according to the settings for
        % the initializer.
        % USAGE: [mass, mom, ener, mag, statics, run] = getInitialConditions();
        potentialField = [];
        selfGravity = [];        
        GIS = GlobalIndexSemantics();

        GIS.makeDimNotCircular(1);

        obj.radiation.type                      = ENUM.RADIATION_OPTICALLY_THIN;
        obj.radiation.exponent                  = obj.radTheta;

        obj.radiation.initialMaximum            = 1; % We do not use these, instead
        obj.radiation.coolLength                = 1; % We let the cooling function define dx
        obj.radiation.strengthMethod            = 'preset';
        obj.radiation.setStrength               = obj.radBeta;

        statics = []; % We'll set this eventually...

        % Gets the jump solution, i.e. preshock and adiabatic postshock solutions
        jump = HDJumpSolver(obj.sonicMach, obj.theta, obj.gamma);
        radflow = RadiatingFlowSolver(jump.rho(2), jump.v(1,2), jump.v(2,2), 0, 0, jump.P(2), ...
                                      obj.gamma, obj.radBeta, obj.radTheta);
        radflow.numericalSetup(2, 2);

        L_c = radflow.coolingLength(jump.v(1,2));
        T_c = radflow.coolingTime(jump.v(1,2));
        [flowState, dSingularity] = radflow.CalculateFlowTable(jump.v(1,2), L_c / 1000, 2*L_c);

        fprintf('Characteristic cooling length: %f\nCharacteristic cooling time:   %f\nDistance to singularity: %f\n', L_c, T_c, dSingularity);

        obj.dGrid = ones(1,3) * obj.fractionTillSingularity * dSingularity ...
                          / ((1-obj.fractionPreshock)*obj.grid(1));

        [vecX vecY vecZ] = GIS.ndgridVecs();

        preshock =  (vecX < obj.grid(1)*obj.fractionPreshock);
        postshock = (vecX >= obj.grid(1)*obj.fractionPreshock);
        numPre = obj.grid(1)*obj.fractionPreshock;

        mass = zeros(GIS.pMySize);
        ener = zeros(GIS.pMySize);
        mom  = zeros([3 GIS.pMySize]);
        mag  = zeros([3 GIS.pMySize]);

        mass(preshock,:,:) = jump.rho(1);
        ener(preshock,:,:) = .5*jump.rho(1)*(jump.v(1,1)^2+jump.v(2,1)^2) ...
                             + jump.P(1)/(obj.gamma-1);
        mom(1,:,:,:) = jump.rho(1)*jump.v(1,1);
        mom(2,preshock,:,:) = jump.rho(1)*jump.v(2,1);
        mom(3,preshock,:,:) = 0;

        % Get interpolated rho values
        minterp = interp1(flowState(:,1)+numPre*obj.dGrid(1), flowState(:,3), vecX*obj.dGrid(1),'cubic');
        vinterp = interp1(flowState(:,1)+numPre*obj.dGrid(1), flowState(:,2), vecX*obj.dGrid(1),'cubic');
        Pinterp = interp1(flowState(:,1)+numPre*obj.dGrid(1), flowState(:,4), vecX*obj.dGrid(1),'cubic');

        for xp = find(postshock)
            mass(xp,:,:) = minterp(xp);
            mom(2,xp,:,:) = minterp(xp)*jump.v(2,2);
            ener(xp,:,:) = .5*minterp(xp)*(vinterp(xp)^2+jump.v(2,2)^2) + Pinterp(xp)/(obj.gamma-1);
        end
 
        %--- Perturb mass density in pre-shock region ---%
        %       Mass density gets perturbed in the pre-shock region just before the shock front
        %       to seed the formation of any instabilities

%{        delta       = ceil(0.12*obj.grid(1));
        seedIndices = (1:10) + obj.grid(1)*obj.fractionPreshock - 20 - GIS.pMyOffset(1);
        mine = find((seedIndices >= 1) & (seedIndices < GIS.pMySize(1)));

        if any(mine);
            switch (obj.perturbationType)
                % RANDOM Seeds ____________________________________________________________________
                case HydroShockInitializer.RANDOM
                    phase = 2*pi*rand(10,obj.grid(2), obj.grid(3));
                    amp   = obj.seedAmplitude*ones(1,obj.grid(2), obj.grid(3))*obj.grid(2)*obj.grid(3);

                    amp(:,max(4, obj.randomSeed_spectrumLimit):end,:) = 0;
                    amp(:,:,max(4, obj.randomSeed_spectrumLimit):end) = 0;
                    amp(:,1,1) = 0; % no common-mode seed

                    perturb = zeros(10, obj.grid(2), obj.grid(3));
                    for xp = 1:size(perturb,1)
                        perturb(xp,:,:) = sin(xp*2*pi/20)^2 * real(ifft(squeeze(amp(1,:,:).*exp(1i*phase(1,:,:)))));
                    end

                case HydroShockInitializer.COSINE
                    [X Y Z] = ndgrid(1:delta, 1:obj.grid(2), 1:obj.grid(3));
                    perturb = obj.seedAmplitude*cos(2*pi*(Y - 1)/(obj.grid(2) - 1)) ...
                                    .*sin(pi*(X - 1)/(delta - 1));
                % COSINE Seeds ____________________________________________________________________
                case HydroShockInitializer.COSINE_2D 
                    [X Y Z] = ndgrid(1:delta, 1:obj.grid(2), 1:obj.grid(3));
                    perturb = obj.seedAmplitude ...
                                *( cos(2*pi*obj.cos2DFrequency*(Y - 1)/(obj.grid(2) - 1)) ...
                                 + cos(2*pi*obj.cos2DFrequency*(Z - 1)/(obj.grid(3) - 1)) ) ...
                                 .*sin(pi*(X - 1)/(delta - 1));

                % Unknown Seeds ___________________________________________________________________
                 otherwise
                    error('Imogen:CorrugationShockInitializer', ...
                          'Uknown perturbation type. Aborted run.');
            end

            seeds = seedIndices(mine);

            mass(seedIndices,:,:) = squeeze( mass(seedIndices,:,:) ) + perturb;
            % Add seed to mass while maintaining self-consistent momentum/energy
            % This will otherwise take a dump on e.g. a theta=0 shock with
            % a large density fluctuation resulting in negative internal energy
            mom(1,seedIndices,:,:) = squeeze(mass(seedIndices,:,:)) * jump.v(1,1);
            mom(2,seedIndices,:,:) = squeeze(mass(seedIndices,:,:)) * jump.v(2,1);

            ener(seedIndices,:,:) = .5*squeeze(mass(seedIndices,:,:))*(jump.v(1,1).^2+jump.v(2,1).^2) + jump.P(1)/(obj.gamma-1);

        end
        
            if obj.useGPU == true
                statics = StaticsInitializer(); 

                %statics.setFluid_allConstantBC(mass, ener, mom, 1);
                %statics.setMag_allConstantBC(mag, 1);

                %statics.setFluid_allConstantBC(mass, ener, mom, 2);
                %statics.setMag_allConstantBC(mag, 2);
            end

        end


    end%PROTECTED
        
%===================================================================================================    
    methods (Static = true) %                                                     S T A T I C    [M]
    end
end%CLASS
