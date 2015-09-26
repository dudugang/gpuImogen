classdef KojimaDiskInitializer < Initializer
% Uses equilibrium routines to create an equilibrium disk configuration and then formats them for
% use in Imogen based on the Kojima model. The disk is created in the polytropic unit systems under
% the constraints that the gravitational constant, G, the mass of the central star, M, and the 
% polytropic constant, K, are all unity.
%
% Unique properties for this initializer:
%   q                 angular velocity exponent (omega = omega_0 * r^-q.              double
%   radiusRatio       (inner disk radius) / (radius of density max).                  double
%   edgePadding       number of cells around X & Y edges to leave blank.              double
%   pointRadius       size of the softened point at the center of the grid            double
%   useStatics        specifies if static conditions should be set for the run.       logical
    
        
%===================================================================================================
    properties (Constant = true, Transient = true) %                            C O N S T A N T  [P]
        MOMENTUM_DISTRIB_NONE   = 1;
        MOMENTUM_DISTRIB_KOJIMA = 2;
        MOMENTUM_DISTRIB_KEPLER = 3;
        MOMENTUM_DISTRIB_SOFTEN = 4;
    end%CONSTANT
    
%===================================================================================================
    properties (SetAccess = public, GetAccess = public) %                           P U B L I C  [P]
        q;              % angular velocity exponent; omega = omega_0 * r^-q.            double
        radiusRatio;    % inner radius / radius of density max.                         double
        edgePadding;    % number of cells around X & Y edges to leave blank.            double
        pointRadius;    % size of the softened point at the center of the grid.         double
        diskMomDist;    % 1x4 describes momentum distribution                double [4]
        pointMass;

        bgDensityCoeff; % Min density is this times max initial density            double
        useZMirror;     % If 1 and run is 3d, simulates the top half of the disk only   logical

        useStatics;     % specifies if static conditions should be set for the run.     logical
        inflatePressure;% artificially increase the background pressure.                logical 
    end %PUBLIC

%===================================================================================================
    properties (Dependent = true) %                                            D E P E N D E N T [P]
    end %DEPENDENT
    
%===================================================================================================
    properties (SetAccess = protected, GetAccess = protected) %                P R O T E C T E D [P]
    end %PROTECTED
    
%===================================================================================================
    methods %                                                                     G E T / S E T  [M]
        
%___________________________________________________________________________________________________ KojimaDiskInitializer
        function obj = KojimaDiskInitializer(input)
            obj                     = obj@Initializer();            
            obj.runCode             = 'KOJIMA';
            obj.info                = 'Kojima point-potential disk trial.';
            obj.mode.fluid          = true;
            obj.mode.magnet         = false;
            obj.mode.gravity        = true;
            obj.iterMax             = 300;
            obj.bcMode.x            = ENUM.BCMODE_FADE;
            obj.bcMode.y            = ENUM.BCMODE_FADE;
            obj.bcInfinity          = 5;
            obj.activeSlices.xy     = true;
            obj.timeUpdateMode      = ENUM.TIMEUPDATE_PER_STEP;
            obj.bgDensityCoeff      = 1e-5;
            
            obj.gravity.constant        = 1;
            obj.pointMass               = 1;
            obj.pointRadius             = 0.3;
            obj.gamma                   = 5/3;
            obj.q                       = 2;
            obj.radiusRatio             = 0.8;
            obj.edgePadding             = 0.5;

            obj.thresholdMass           = 0;
            obj.useStatics              = false;
            obj.inflatePressure         = false;
            obj.useZMirror              = 0;
            
            %--- Set momentum distribution array ---%
            %           This array defines how Imogen distributes momentum in the grid. A value of 1 
            %           specifies no momentum, 2 gives Kojima r^1-q momentum, 3 gives Keplerian 
            %           r^-.5, 4 gives a momentum appropriate to the softened potential at the 
            %           center.
            %
            %           First number selects momentum for 0-pointradius.
            %           Second selects momentum for pointradius - radiusRatio.
            %           Third selects momentum for the disk itself.
            %           Fourth selects momentum outside the disk.
            %           Default is zero momentum except in the disk.
            %           In principle [4 3 2 3] is nearest equilibrium but it is violently unstable.
            obj.diskMomDist             = [ KojimaDiskInitializer.MOMENTUM_DISTRIB_NONE, ...
                                                KojimaDiskInitializer.MOMENTUM_DISTRIB_NONE, ...   
                                                KojimaDiskInitializer.MOMENTUM_DISTRIB_KOJIMA, ...
                                                KojimaDiskInitializer.MOMENTUM_DISTRIB_NONE ];
            
            obj.operateOnInput(input, [64 64 1]);
            
        end
        
%___________________________________________________________________________________________________ GS: pointMass
% Dynmaic pointMass property to connect between the gravity vars structure and run files.
    
    end%GET/SET
    
%===================================================================================================
    methods (Access = public) %                                                     P U B L I C  [M]
    end%PUBLIC
    
%===================================================================================================    
    methods (Access = protected) %                                          P R O T E C T E D    [M]                
        
%___________________________________________________________________________________________________ calculateInitialConditions
        function [mass, mom, ener, mag, statics, potentialField, selfGravity] = calculateInitialConditions(obj)

%            if (obj.grid(3) > 1)
%                if obj.useZMirror == 1
%                    obj.bcMode.z    = ENUM.BCMODE_FLIP;
%                else
%                    obj.bcMode.z    = ENUM.BCMODE_FADE; 
%                end
%            else
%                obj.bcMode.z    = ENUM.BCMODE_CONST;
%            end

            obj.frameRotateOmega = 1;
            obj.frameRotateCenter = [obj.grid(1) obj.grid(2)]/2 + .5;

            GIS = GlobalIndexSemantics();
            GIS.setup(obj.grid);

            mom     = GIS.zerosXYZ(GIS.VECTOR);
            
            [mass, mom(1,:,:,:), mom(2,:,:,:), dGrid] = kojimaDisc1(obj.q, obj.gamma, ...
                            obj.radiusRatio, obj.grid, 1, obj.edgePadding, obj.pointRadius, ...
                            obj.bgDensityCoeff, obj.diskMomDist, obj.useZMirror);

            obj.appendInfo(sprintf('Automatically set dGrid uniformly to %d', dGrid));
            obj.dGrid = dGrid*ones(1,3);
           
            tempd = cell(1,3);
            tempd{1} = obj.dGrid(1); tempd{2} = obj.dGrid(2); tempd{3} = obj.dGrid(3);
 
            obj.minMass = maxFinderND(mass) * obj.bgDensityCoeff;

            mass    = max(mass, obj.minMass);
            mag     = GIS.zerosXYZ(GIS.VECTOR);
            
            if obj.inflatePressure
                minDiskMass = minFinderND(mass(mass > obj.minMass));
            else
                minDiskMass = obj.minMass;
            end
            
            ener    = (max(mass, minDiskMass).^obj.gamma)/(obj.gamma - 1) ...   % internal energy
                        + 0.5*squeeze(sum(mom .* mom, 1)) ./ mass ...           % kinetic energy
                        + 0.5*squeeze(sum(mag .* mag, 1));                      % magnetic energy                    
            
statics = [];%StaticsInitializer(obj.grid);

%statics.setFluid_allConstantBC(mass, ener, mom, 1);
%statics.setMag_allFadeBC(mag, 1, 25);

%statics.setFluid_allConstantBC(mass, ener, mom, 2);
%statics.setMag_allFadeBC(mag, 2, 25);           
            starX = (obj.grid+1)*dGrid/2;

            selfGravity = SelfGravityInitializer();
            selfGravity.compactObjectStates = [1 obj.pointRadius starX(1) starX(2) starX(3) 0 0 0 0 0 0];
                                           % [m R x y z vx vy vz lx ly lz]

            potentialField = [];%PotentialFieldInitializer();

%            if obj.useZMirror == 1
%                potentialField.field = grav_GetPointPotential(obj.grid, tempd, ...
%                [obj.grid(1)/2 obj.grid(2)/2 0] + [.5 .5 0], 1, obj.pointRadius); % Temporary kludge
%            else
%                potentialField.field = grav_GetPointPotential(obj.grid, tempd, ...
%                obj.grid/2 + [.5 .5 .5], 1, obj.pointRadius); % Temporary kludge
%            end
        end
        
    end%PROTECTED
        
%===================================================================================================    
    methods (Static = true) %                                                     S T A T I C    [M]
    end
end%CLASS
