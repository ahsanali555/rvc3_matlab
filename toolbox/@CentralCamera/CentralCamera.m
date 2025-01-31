%CentralCamera  Perspective camera class
%
% A concrete class for a central-projection perspective camera, a subclass of
% Camera.
%
% The camera coordinate system is:
%
%         0------------> u X
%         |
%         |
%         |   + (principal point)
%         |
%         |   Z-axis is into the page.
%         v Y
%
% This camera model assumes central projection, that is, the focal point
% is at z=0 and the image plane is at z=f.  The image is not inverted.
%
% Methods::
%
% project          project world points and lines
% K                camera intrinsic matrix
% C                camera matrix
% H                camera motion to homography
% invH             decompose homography
% F                camera motion to fundamental matrix
% E                camera motion to essential matrix
% invE             decompose essential matrix
% fov              field of view
% ray              Ray3D corresponding to point
% center           projective center
% normalized       convert image plane coordinate to normalized coordinates
%-
% plot             plot projection of world point on image plane
% hold             control hold for image plane
% ishold           test figure hold for image plane
% clf              clear image plane
% figure           figure holding the image plane
% mesh             draw shape represented as a mesh
% point            draw homogeneous points on image plane
% line             draw homogeneous lines on image plane
% plot_camera      draw camera in world view
% plot_line_tr     draw line in theta/rho format
% plot_epiline     draw epipolar line
%-
% flowfield        compute optical flow
% visjac_p         image Jacobian for point features
% visjac_p_polar   image Jacobian for point features in polar coordinates
% visjac_l         image Jacobian for line features
% visjac_e         image Jacobian for ellipse features
% derivs           point and camera motion Jacobians for bundle adjustment      
%-
% rpy              set camera attitude
% move             clone Camera after motion
% center           get world coordinate of camera center
% estpose          estimate pose
%-
% delete           object destructor
% char             convert camera parameters to string
% display          display camera parameters
%-
% Properties (read/write)::
% npix         image dimensions in pixels (1x2)
% pp           intrinsic: principal point (1x2)
% rho          intrinsic: pixel dimensions (1x2) in metres
% f            intrinsic: focal length
% k            intrinsic: radial distortion vector
% p            intrinsic: tangential distortion parameters
% distortion   intrinsic: camera distortion [k1 k2 k3 p1 p2]
% T            extrinsic: camera pose as homogeneous transformation
%
% Properties (read only)::
% nu    number of pixels in u-direction
% nv    number of pixels in v-direction
% u0    principal point u-coordinate
% v0    principal point v-coordinate
%
% Notes::
%  - Camera is a reference object.
%  - Camera objects can be used in vectors and arrays
%
% See also Camera.

% Copyright 2022-2023 Peter Corke, Witold Jachimczyk, Remo Pillat 

%TODO
% method to undo lens distortion


classdef CentralCamera < Camera

    properties
        f       % focal length
        k       % radial distortion vector
        p       % tangential distortion parameters
        distortion  % camera distortion [k1 k2 k3 p1 p2]
    end

    properties (SetAccess = private)
    end

    properties (GetAccess = private, SetAccess = private)

    end

    properties (GetAccess = private)
    end

    properties (Dependent = true, SetAccess = private)
    end

    methods

        function c = CentralCamera(varargin)
        %CentralCamera.CentralCamera Create central projection camera object
        %
        % C = CentralCamera() creates a central projection camera with canonic
        % parameters: f=1 and name='canonic'.
        %
        % C = CentralCamera(OPTIONS) as above but with specified parameters.
        %
        % Options::
        % 'name',N                  Name of camera
        % 'focal',F                 Focal length [metres]
        % 'distortion',D            Distortion vector [k1 k2 k3 p1 p2]
        % 'distortion-bouguet',D    Distortion vector [k1 k2 p1 p2 k3]
        % 'default'                 Default camera parameters: 1024x1024, f=8mm,
        %                           10um pixels, camera at origin, optical axis
        %                           is z-axis, u- and v-axes parallel to x- and 
        %                           y-axes respectively.
        % 'canonic'                 Default camera parameters: 1024x1024, f=1,
        %                           retinal coordinates, camera at origin, optical axis
        %                           is z-axis, u- and v-axes parallel to x- and 
        %                           y-axes respectively.
        % 'resolution',N            Image plane resolution: NxN or N=[W H]
        % 'sensor',S                Image sensor size in metres (2x1)
        % 'center',P                Principal point (2x1)
        % 'pixel',S                 Pixel size: SxS or S=[W H]
        % 'noise',SIGMA             Standard deviation of additive Gaussian 
        %                           noise added to returned image projections
        % 'pose',T                  Pose of the camera as a homogeneous 
        %                           transformation
        % 'color',C                 Color of image plane background (default [1 1 0.8])
        % 'image',IM                Display an image rather than points
        % 'distance',D              If 'image' and 'focal' options are used, then compute
        %                           pixel size based on assumed distance D of image.                     
        %
        % See also Camera, FisheyeCamera, CatadioptricCamera, SphericalCamera.

            % invoke the superclass constructor to handle common options
            c = c@Camera(varargin{:});
            c.type = 'central-perspective';
            c.perspective = true;

            if nargin == 1 && isa(varargin{1}, 'CentralCamera')
                % copy constructor
                old = varargin{1};
                for p=properties(c)'
                    % copy each property across, exceptions occur
                    % for those with protected SetAccess
                    p = p{1};
                    try
                        c = setfield(c, p, getfield(old, p));
                    end
                end
                return
            end

            if isempty(c.pp) && ~isempty(c.npix)
                c.pp = c.npix/2;
            elseif isempty(c.pp)
                c.pp =[0 0];
            end

            % process remaining options
            opt.focal = [];
            opt.distortion = [];
            opt.distortion_bouguet = [];
            opt.model = {[], 'default', 'canonic'};
            opt.image = [];
            opt.distance = [];

                
            [opt,args] = tb_optparse(opt, varargin);

            % assign defaults first, the remaining options can modify
            % these settings.
            if ~isempty(opt.model)
                switch opt.model
                case 'canonic'
                    c.f = 1;
                    c.distortion = [];
                    c.pp = [0 0];
                    c.name = 'canonic';
                case 'default'
                    c.f = 8e-3;     % f
                    c.rho = [10e-6, 10e-6];      % square pixels 10um side
                    c.npix = [1024, 1024];  % 1Mpix image plane
                    c.pp = [512, 512];      % principal point in the middle
                    c.limits = [0 1024 0 1024];
                    c.name = 'default';
                end
            end
            
            % override default focal length
            if ~isempty(opt.focal)
                c.f = opt.focal;
            end
            if isempty(c.f)
                warning('Focal length not set');
            end
            
            if ~isempty(opt.image)
                c.name = 'image';
            end
            
            if ~isempty(opt.distance)
                c.rho = c.f / opt.distance;
            end
            
            if ~isempty(opt.distortion)
                if length(opt.distortion) == 5
                    c.distortion = opt.distortion;
                else
                    error('distortion vector is [k1 k2 k3 p1 p2]');

                end
            end
            if ~isempty(opt.distortion_bouguet)
                if length(opt.distortion_bouguet) == 5
                    c.distortion = [v(1) v(2) v(5) v(3) v(4)];
                else
                    error('distortion vector is [k1 k2 p1 p2 k3]');
                end
            end
        end

    	function camInt = intrinsics(c)

            pixelDims = c.rho; % in meters
            focalLenInPix = (c.f)./pixelDims;
            imSize = [c.nv, c.nu];
            principalPoint = c.pp;
            camInt = cameraIntrinsics(focalLenInPix, principalPoint, imSize);

        end
		

        function s = char(c)

            s = sprintf('name: %s [%s]', c.name, c.type);
            s = strvcat(s, sprintf(    '  focal length:   %-11.4g', c.f));
            if ~isempty(c.distortion)
                s = strvcat(s, sprintf('  distortion:     k=(%.4g, %.4g, %.4g), p=(%.4g, %.4g)', c.distortion));
            end
            s = strvcat(s, char@Camera(c) );
        end

        function v = K(c)
        %CentralCamera.K Intrinsic parameter matrix
        %
        % K = C.K() is the 3x3 intrinsic parameter matrix.
            v = [   c.f/c.rho(1)   0           c.pp(1) 
                    0          c.f/c.rho(2)    c.pp(2)
                    0          0           1%/c.f
                ] ;
        end

        function v = C(c, Tcam)
        %CentralCamera.C Camera matrix
        %
        % C = C.C() is the 3x4 camera matrix, also known as the camera 
        % calibration or projection matrix.
        %
        % C = C.C(T) as above but for the camera at pose T (se3).
            if nargin == 1
                Tcam = c.T;
            end
            Tcam = se3(Tcam);

            if isempty(c.rho)
                rho = [1 1];
            else
                rho = c.rho;
            end

            v = [   c.f/rho(1)     0           c.pp(1)   0
                    0            c.f/rho(2)    c.pp(2)   0
                    0            0           1         0
                ] * Tcam.inv().tform;
        end

        function HH = H(c, T, n, d)
        %CentralCamera.H Homography matrix
        %
        % H = C.H(T, N, D) is a 3x3 homography matrix for the camera observing the plane
        % with normal N and at distance D, from two viewpoints.  The first view is from 
        % the current camera pose C.T and the second is after a relative motion represented
        % by the homogeneous transformation T.
        %
        % See also CentralCamera.H.
            
            if (d < 0) || (n(3) < 0)
                error('plane distance must be > 0 and normal away from camera');
            end
            
            % T is the transform from view 1 to view 2
            % (R,t) is the inverse
            T = inv(T);
            
            R = t2r( T );
            t = transl( T );

            HH = R + 1.0/d*t*n(:)';

            % now apply the camera intrinsics
            K = c.K
            HH = K * HH * inv(K);
            HH = HH / HH(3,3);     % normalize it
        end
        
        function s = invH(c, H, varargin)
        %CentralCamera.invH Decompose homography matrix
        %
        % S = C.invH(H) decomposes the homography H (3x3) into the camera motion
        % and the normal to the plane.
        %
        % In practice there are multiple solutions and S is a vector of structures 
        % with elements:
        %  - T, camera motion as a homogeneous transform matrix (4x4), translation not to scale
        %  - n, normal vector to the plane (3x3)
        %
        % Notes::
        % - There are up to 4 solutions
        % - Only those solutions that obey the positive depth constraint are returned
        % - The required camera intrinsics are taken from the camera object
        % - The transformation is from view 1 to view 2.
        %
        %
        % Reference::
        % Y.Ma, J.Kosecka, S.Soatto, S.Sastry,
        % "An invitation to 3D",
        % Springer, 2003.
        % section 5.3
        %
        % See also CentralCamera.H.

            if nargout == 0
                invhomog(H, 'K', c.K, varargin{:});
            else
                s = invhomog(H, 'K', c.K, varargin{:});
            end
        end
        
        function fmatrix = F(c, X)
        %CentralCamera.F Fundamental matrix
        %
        % F = C.F(T) is the fundamental matrix relating two camera views.  The first
        % view is from the current camera pose C.T and the second is a relative motion
        % represented by the homogeneous transformation T.
        %
        % F = C.F(C2) is the fundamental matrix relating two camera views described
        % by camera objects C (first view) and C2 (second view).
        %
        % Reference::
        % Y.Ma, J.Kosecka, S.Soatto, S.Sastry,
        % "An invitation to 3D",
        % Springer, 2003.
        % p.177
        %
        % See also CentralCamera.E.
            
            
            % T is the pose for view 1 
            % c.T is the pose for view 2

            if istform(X)
                E = c.E(X);
                K = c.K();
                fmatrix = inv(K)' * E * inv(K);
            elseif  isa(X, 'Camera')
                % use relative pose and camera parameters of 
                E = c.E(X);
                K1 = c.K;
                K2 = X.K();
                fmatrix = inv(K2)' * E * inv(K1);
            end
        end
        
        function ematrix = E(c, X)
        %CentralCamera.E Essential matrix
        %
        % E = C.E(T) is the essential matrix relating two camera views.  The first
        % view is from the current camera pose C.T and the second is a relative motion
        % represented by the homogeneous transformation T.
        %
        % E = C.E(C2) is the essential matrix relating two camera views described
        % by camera objects C (first view) and C2 (second view).
        %
        % E = C.E(F) is the essential matrix based on the fundamental matrix F (3x3)
        % and the intrinsic parameters of camera C.
        %
        % Reference::
        % Y.Ma, J.Kosecka, S.Soatto, S.Sastry,
        % "An invitation to 3D",
        % Springer, 2003.
        % p.177
        %
        % See also CentralCamera.F, CentralCamera.invE.

            % essential matrix from pose.  Assume the first view is associated
            % with the passed argument, either a hom.trans or a camera.
            % The second view is Tcam of this object.
            if ismatrix(X) && all(size(X) == [3 3]),
                % essential matrix from F matrix
                F = X;

                K = c.K();
                ematrix = K'*F*K;
                return;
            elseif isa(X, 'Camera')
                T21 = inv(X.T) * c.T;
            elseif isa(X, 'se3')
                T21 = inv(X);
            else
                error('unknown argument type');
            end

            R = T21.rotm;
            t = T21.trvec;
            
            ematrix = skew(t) * R;
        end
        
        function s = invE(c, E, P)
        %CentralCamera.invE Decompose essential matrix
        %
        % S = C.invE(E) decomposes the essential matrix E (3x3) into the camera motion.
        % In practice there are multiple solutions and S (4x4xN) is a set of homogeneous
        % transformations representing possible camera motion.
        %
        % S = C.invE(E, P) as above but only solutions in which the world point P is visible
        % are returned.
        %
        % Reference::
        % Hartley & Zisserman, 
        % "Multiview Geometry",
        % Chap 9, p. 259
        %
        % Y.Ma, J.Kosecka, S.Soatto, S.Sastry,
        % "An invitation to 3D",
        % Springer, 2003.
        % p116, p120-122
        %
        % Notes::
        % - The transformation is from view 1 to view 2.
        %
        % See also CentralCamera.E.

            % we return T from view 1 to view 2
            
            [U,S,V] = svd(E);
            % singular values are (sigma, sigma, 0)
            
% %                 % H&Z solution
% %                 W = [0 -1 0; 1 0 0; 0 0 1];   % rotz(pi/2)
% % 
% %                 t = U(:,3);
% %                 R1 = U*W*V';
% %                 if det(R1) < 0,
% %                     disp('flip');
% %                     V = -V;
% %                     R1 = U*W*V';
% %                     det(R1)
% %                 end
% %                 R2 = U*W'*V';
% % 
% %                 % we need to invert the solutions since our definition of pose is
% %                 % from initial camera to the final camera
% %                 s(:,:,1) = inv([R1 t; 0 0 0 1]);
% %                 s(:,:,2) = inv([R1 -t; 0 0 0 1]);
% %                 s(:,:,3) = inv([R2 t; 0 0 0 1]);
% %                 s(:,:,4) = inv([R2 -t; 0 0 0 1]);

% Ma etal solution, p116, p120-122
                % Fig 5.2 (p113), is wrong, (R,t) is from camera 2 to 1
                if det(V) < 0
                    V = -V;
                    S = -S;
                end
                if det(U) < 0
                    U = -U;
                    S = -S;
                end
                R1 = U*rotz(pi/2)'*V';
                R2 = U*rotz(-pi/2)'*V';
                t1 = skew2vec(U*rotz(pi/2)*S*U');
                t2 = skew2vec(U*rotz(-pi/2)*S*U');
                % invert (R,t) so its from camera 1 to 2
%                 s(1) = SE3( inv( [R1 t1; 0 0 0 1] ) );
%                 s(2) = SE3( inv( [R2 t2; 0 0 0 1] ) );

                s = repmat(se3, [1, 2])  % preallocation is necessary
                s(1) = se3(R1, t1').inv();
                s(2) = se3(R2, t2').inv();
            
            if nargin > 2
                % we're given a test point
                for i=1:length(s)
                    if ~any(isnan(c.project(P, 'pose', s(i))))
                        s = s(i);
                        fprintf('solution %d is good\n', i);
                        return;
                    end
                end
                warning('no solution has given a point in front of camera');
            end
        end
        
        function pn = normalized(cam, p)
        %CentralCamera.normalized  Convert to normalized coordinate
        %
        % cam.normalized(P) converts the image plane coordinate P (2x1) to
        % normalized/retinal coordinates.
        %
        % See also CentralCamera.project.
            pn = homtrans( inv(cam.K), p );
        end
        
        function plot_line_tr(cam, lines, varargin)
        %CentralCamera.plot_line_tr  Plot line in theta-rho format
        %
        % CentralCamera.plot_line_tr(L) plots lines on the camera's image plane that
        % are described by columns of L with rows theta and rho respectively.
        %
        % See also Hough.

            x = get(cam.h_imageplane, 'XLim');
            y = get(cam.h_imageplane, 'YLim');

            % plot it
            for i=1:numcols(lines)
                theta = lines(1,i);
                rho = lines(2,i);
                %fprintf('theta = %f, d = %f\n', line.theta, line.rho);
                if abs(cos(theta)) > 0.5,
                    % horizontalish lines
                    plot(x, -x*tan(theta) + rho/cos(theta), varargin{:}, 'Parent', cam.h_imageplane);
                else
                    % verticalish lines
                    plot( -y/tan(theta) + rho/sin(theta), y, varargin{:}, 'Parent', cam.h_imageplane);
                end
            end
        end

        function handles = plot_epiline(c, F, p, varargin)
        %CentralCamera.plot_epiline Plot epipolar line
        %
        % C.plot_epiline(F, P) plots the epipolar lines due to the fundamental matrix F
        % and the image points P.
        %
        % C.plot_epiline(F, P, LS) as above but draw lines using the line style arguments LS.
        %
        % H = C.plot_epiline(F, P) as above but return a vector of graphic handles, one per
        % line.

            % for all input points
            l = F * e2h(p)';

            c.homline(l, varargin{:});
        end

        function th = fov(c)
        %CentralCamera.fov Camera field-of-view angles.
        %
        % A = C.fov() are the field of view angles (2x1) in radians for the camera x and y
        % (horizontal and vertical) directions.
            try
                th = 2*atan(c.npix/2.*c.rho / c.f);
            catch
                error('MVTB:CentralCamera.fov:badarg', 'npix or rho properties not set');
            end
        end



        function [uv,visible] = project(c, P, varargin)
        %CentralCamera.project Project world points to image plane
        %
        % UV = C.project(P, OPTIONS) are the image plane coordinates (Nx2) corresponding
        % to the world points P (Nx3).
        %
        % [UV,VIS] = C.project(P, OPTIONS) as above but VIS (SxN) is a logical matrix with
        % elements true (1) if the point is visible, that is, it lies within the bounds of
        % the image plane and is in front of the camera.
        %
        % L = C.project(PL, OPTIONS) are the image plane homogeneous lines (3xN) corresponding
        % to the world lines represented by a vector of Plucker objects (1xN).
        %
        % Options::
        % 'pose',T      Set the camera pose to the homogeneous transformation T before
        %               projecting points to the camera image plane.  Temporarily overrides 
        %               the current camera pose C.T.
        % 'objpose',T   Transform all points by the homogeneous transformation T before
        %               projecting them to the camera image plane.
        %
        % Notes::
        % - If camera pose is a vector (1xN), a camera trajectory, then UV (2xNxS) represents 
        %   the sequence of projected points as the camera moves in the world.
        % - If object pose is a vector (1xN), an object trajectory, then UV (2xNxS) represents 
        %   the sequence of projected points as the object moves in the world.
        % - Moving camera and object is not supported
        % - A camera or object pose sequence is not supported for the case of line projection.
        % - (u,v) values are set to NaN if the corresponding point is behind the camera.
        %
        % See also Camera.plot, CentralCamera.normalized, Plucker.

        % - TODO Currently a camera or object pose sequence is not supported for
        %   the case of line projection.


            opt.objpose = [];
            opt.pose = [];

            opt = tb_optparse(opt, varargin);

            np = size(P,2);
            
            if ~isempty(opt.objpose)
                opt.objpose = se3(opt.objpose);
            end
            if ~isempty(opt.pose)
                opt.pose = se3(opt.pose);
            end
                        
            if isempty(opt.pose)
                opt.pose = c.T;
            end
            opt.pose = se3(opt.pose);  % ensure it's an se3 object

            if length(opt.objpose) > 1 && length(opt.pose) > 1
                error('cannot animate object and camera simultaneously');
            end

            if isa(P, 'Plucker')
                % project lines
                % get camera matrix for this camera pose
                C = c.C(opt.pose);
                for i=1:length(P)
                    l = skew2vec( C * P(i).skew * C');
                    uv(i,:) = (l / max(abs(l)))'; % normalize by largest element
                end
            else
                % project points
                if length(opt.objpose) > 1
                    % animate object motion, static camera
                    
                    % get camera matrix for this camera pose
                    C = c.C(opt.pose);
                    
                    % make the world points homogeneous
                    if size(P,2) == 3
                        P = e2h(P);
                    end
                    
                    for frame=1:length(opt.objpose)
                        
                        % transform all the points to camera frame
                        X = (C * opt.objpose(frame).T * P')';     % project them
                        
                        X(X(:,3)<0,3) = NaN;    % points behind the camera are set to NaN

                        X = h2e(X);            % convert to Euclidean coordinates
                        
                        if ~isempty(c.distortion)
                            X = distort(c, X);
                        end
                        
                        if c.noise
                            % add Gaussian noise with specified standard deviation
                            X = X + diag(c.noise) * randn(size(X));
                        end                            
                        
                        uv(:,:,frame) = X;
                    end
                    
                    if nargout > 1
                        % do visibility check if required
                        
                        visible = ~isnan(uv(1,:,:)) & ...
                            uv(1,:,:) >= 1 & uv(2,:,:) >= 1 & ...
                            uv(1,:,:) <= c.npix(2) & uv(2,:,:) <= c.npix(1);
                        visible = squeeze(visible)';
                    end
                    
                else
                    % animate camera, static object
                    
                    % transform the object
                    if ~isempty(opt.objpose)
                        P = homtrans(opt.objpose.tform, P);
                    end
                    
                    % make the world points homogeneous
                    if size(P,2) == 3
                        P = e2h(P);
                    end
                    
                    for frame=1:length(opt.pose)
                        C = c.C(opt.pose(frame));
                        
                        % transform all the points to camera frame
                        X = (C * P')';              % project them
                        X(X(:,3)<0,3) = NaN;    % points behind the camera are set to NaN
                        
                        X = h2e(X);            % convert to Euclidean coordinates
                                        
                        if ~isempty(c.distortion)
                            X = distort(c, X);
                        end
                        
                        if c.noise
                            % add Gaussian noise with specified standard deviation
                            X = (X' + diag(c.noise) * randn(size(X')))';
                        end                        
                        
                        uv(:,:,frame) = X;
                        
                        if nargout > 1
                            % do visibility check if required
                            
                            visible = ~isnan(uv(1,:,:)) & ...
                                uv(1,:,:) >= 0 & uv(2,:,:) >= 0 & ...
                                uv(1,:,:) <= c.npix(1) & uv(2,:,:) <= c.npix(2);
                            visible = squeeze(visible)';
                        end                              
                    end
                end               
            end
            
            function Xd = distort(c, X)
                %CentralCamera.distort Compute distorted coordinate
                %
                % Xd = cam.distort(X) is the projected image plane point X (2x1) after 
                % lens distortion has been applied.
                
                X = inv(c.K) * X;   % convert to normalized image coordinates
                u = X(1,:); v = X(2,:); % unpack coordinates
                k = c.distortion(1:3); p = c.distortion(4:5); % unpack distortion vector
                r = sqrt( u.^2 + v.^2 ); % distance from princ point
                
                % compute the shift due to distortion
                delta_u = u .* (k(1)*r.^2 + k(2)*r.^4 + k(3)*r.^6) + ...
                    2*p(1)*u.*v + p(2)*(r.^2 + 2*u.^2);
                delta_v = v .* (k(1)*r.^2 + k(2)*r.^4 + k(3)*r.^6) + ...
                    p(1)*(r.^2 + 2*v.^2) + 2*p(1)*u.*v;
                
                ud = u + delta_u;  vd = v + delta_v; % distorted coordinates
                Xd = c.K * e2h( [ud; vd] ); % convert to pixel coords
            end
        end

        function r = ray(cam, p)
        %CentralCamera.ray 3D ray for image point
        %
        % R = C.ray(P) returns a vector of Ray3D objects, one for each point
        % defined by the columns of P.
        %
        % Reference::
        %
        % Hartley & Zisserman, 
        % "Multiview Geometry",
        % p 162
        %
        % See also Ray3D.

            C = cam.C();
            Mi = inv(C(1:3,1:3));
            v = C(:,4);
            for i=1:numcols(p)
                r(i) = Ray3D(-Mi*v, Mi*e2h(p(:,i)));
            end
        end
        
        function p = center(cam)
        %CentralCamera.ray Projective center
        %
        % P = C.center() returns the 3D world coordinate of the projective
        % center of the camera.
        %
        % Reference::
        %
        % Hartley & Zisserman, 
        % "Multiview Geometry",
        %
        % See also Ray3D.

          C = cam.C(); 
          Mi = inv(C(1:3,1:3)); 
          v = C(:,4);
          
          p = (-Mi*v)';
        end

        function hg = drawCamera(cam, varargin)

            hold on

            opt.color = 'b';
            opt.mode = {'solid', 'mesh'};
            opt.label = false;
            opt.scale = 1/3;
            opt = tb_optparse(opt, varargin);
            
            s = opt.scale;

            % create a new transform group
            hg = hgtransform;

            % the box is centered at the origin and its centerline parallel to the
            % z-axis.  Its z-extent is -bh/2 to bh/2.
            bw = 0.5;       % half width of the box
            bh = 1.2;       % height of the box
            cr = 0.4;       % cylinder radius
            ch = 0.8;       % cylinder height
            cn = 16;        % number of facets of cylinder
            a = 3;          % length of axis line segments

            opt.parent = hg;

            % draw the box part of the camera
            r = bw*[1; 1];
            x = r * [1 1 -1 -1 1];
            y = r * [1 -1 -1 1 1];
            z = [-bh; bh]/2 * ones(1,5);
            draw(x,y,z, opt);

            % draw top and bottom of box
            x = bw * [-1 1; -1 1];
            y = bw * [1 1; -1 -1];
            z = [1 1; 1 1];

            draw(x,y,-bh/2*z, opt);
            draw(x,y,bh/2*z, opt);


            % draw the lens
            [x,y,z] = cylinder(cr, cn);
            z = ch*z+bh/2;
            h = draw(x,y,z, opt);
            set(h, 'BackFaceLighting', 'unlit');

            % draw the x-, y- and z-axes
            plot3([0,a*s], [0,0], [0,0], 'k', 'Parent', hg);
            text(a*s, 0, 0, sprintf(' X'), 'Parent', hg);
            plot3([0,0], [0,a*s], [0,0], 'k', 'Parent', hg);
            text(0, a*s, 0, sprintf(' Y'), 'Parent', hg);
            plot3([0,0], [0,0], [0,a*s], 'k', 'Parent', hg);
            text(0, 0, a*s, sprintf(' Z'), 'Parent', hg);

            if opt.label
                text( 0.3*a*s, 0.1*a*s, 0, cam.name, 'Parent', hg);
            end
            hold off


            function h = draw(x, y, z, opt)

                s = opt.scale;
                switch opt.mode
                case 'solid'
                    h = surf(x*s,y*s,z*s, 'FaceColor', opt.color);
                case 'surfl'
                    h = surfl(x*s,y*s,z*s, 'FaceColor', opt.color);
                case 'mesh'
                    h = mesh(x*s,y*s,z*s, 'EdgeColor', opt.color, 'FaceColor', 'none');
                end

                set(h, 'Parent', opt.parent);
            end
        end
        
        function [p,JA,JB] = derivs(cam, t,qv,P)
            %CentralCamera.derivs Compute bundle adjustment Jacobians
            %
            % [P,JA,JB] = cam.derivs(T, QV, X) computes the image plane projection
            % P (2x1), Jacobian dP/dV (2x6) and Jacobian dP/dX (2x3) given the world
            % point X (3x1) and the camera position T (3x1) and orientation QV (3x1).
            %
            % Orientation is expressed as the vector part of a unit-quaterion.
            %
            % Notes::
            % - The Jacobians are used to compute the approximate Hessian for bundle
            %   adjustment problems based on camera observations of landmarks.
            % - This is optimized automatically generated code.
            %
            % See also UnitQuaternion, UnitQuaternion.tovec.
            
            %    This function was generated by the Symbolic Math Toolbox version 6.3.
            %    04-Nov-2015 15:51:31
            
%             %          [p,JA,JB] = cameraModel(tx, ty, tz, qx, qy, qz, Px, Py, Pz, f, rhox, rhoy, u0, v0)
%             %
%             % which computes the image plane projection and two Jacobians, where the camera position is (tx,ty,tz), orientation given by quaternion
%             % vector component (qx,qy,qz), world point (Px,Py,Pz) and intrinsics (f,
%             % rhox, rhoy,u0,v0).  Assumes a standard projective camera model.
%             
%             % intrinsics
%             syms u0 v0 rhox rhoy f real
%             K = [f/rhox 0 u0; 0 f/rhoy v0; 0 0 1]
%             
%             % world point
%             P = sym('P', [3,1], 'real');
%             
%             % camera translation
%             t = sym('T', [3,1], 'real');
%             
%             % camera rotation
%             % - scalar part of quaternion is a function of the vector part
%             %   which we keep as the camera rotation state
%             syms qs qx qy real
%             qz = sym('qz', 'real'); % since qz is a builtin function :(
%             qs = sqrt(1- qx^2 - qy^2 - qz^2);
%             R = UnitQuaternion.q2r([qs qx qy qz]);
%             
%             % camera projection model
%             %  - homogeneous
%             uvw = K * (R'*P - R'*t);
%             
%             %  - Euclidean
%             uv = uvw(1:2) ./ uvw(3);
%             uv = simplify(uv)
%             
%             % compute the Jacobians
%             A = jacobian(uv, [t' qx qy qz]);  % wrt camera pose
%             B = jacobian(uv, P);              % wrt landmark position
%             
%             % generate a function
%             fprintf('creating file --> cameraModel.m\n');
%             matlabFunction(uv, A, B, 'file', 'cameraModel', ...
%                 'Vars', [t(1) t(2) t(3) qx qy qz P(1) P(2) P(3) f rhox rhoy u0 v0]);
            
            
            
            f = cam.f;
            rhox = cam.rho(1); rhoy = cam.rho(2);
            u0 = cam.u0; v0 = cam.v0;
            
            % autogenerated code below
            t2 = qv(1).^2;
            t3 = t2.*2.0;
            t4 = qv(2).^2;
            t5 = t4.*2.0;
            t6 = t3+t5-1.0;
            t7 = qv(3).^2;
            t8 = -t2-t4-t7+1.0;
            t9 = sqrt(t8);
            t10 = conj(t9);
            t11 = qv(1).*qv(3).*2.0;
            t12 = qv(2).*t10.*2.0;
            t13 = t11+t12;
            t14 = qv(2).*qv(3).*2.0;
            t23 = qv(1).*t10.*2.0;
            t15 = t14-t23;
            t16 = t7.*2.0;
            t17 = t5+t16-1.0;
            t18 = qv(1).*qv(2).*2.0;
            t19 = qv(3).*t10.*2.0;
            t20 = t18+t19;
            t21 = t11-t12;
            t22 = P(3).*t6;
            t24 = t(1).*t13;
            t25 = t(2).*t15;
            t27 = t(3).*t6;
            t28 = P(1).*t13;
            t29 = P(2).*t15;
            t26 = t22+t24+t25-t27-t28-t29;
            t30 = t3+t16-1.0;
            t31 = t18-t19;
            t32 = t14+t23;
            t33 = 1.0./t26;
            t34 = 1.0./rhox;
            t35 = t26.*u0;
            t36 = P(1).*t17;
            t37 = t(2).*t20;
            t38 = t(3).*t21;
            t42 = t(1).*t17;
            t43 = P(2).*t20;
            t44 = P(3).*t21;
            t39 = t36+t37+t38-t42-t43-t44;
            t40 = f.*t34.*t39;
            t41 = t35+t40;
            t45 = 1.0./t26.^2;
            t46 = qv(3).*2.0;
            t47 = 1.0./t10;
            t51 = qv(1).*qv(2).*t47.*2.0;
            t48 = t46-t51;
            t49 = t10.*2.0;
            t57 = t2.*t47.*2.0;
            t50 = t49-t57;
            t52 = qv(2).*2.0;
            t69 = qv(1).*qv(3).*t47.*2.0;
            t53 = t52-t69;
            t54 = t46+t51;
            t55 = P(3).*qv(1).*4.0;
            t56 = t(1).*t48;
            t58 = P(2).*t50;
            t87 = t(3).*qv(1).*4.0;
            t88 = P(1).*t48;
            t89 = t(2).*t50;
            t59 = t55+t56+t58-t87-t88-t89;
            t63 = t4.*t47.*2.0;
            t60 = t49-t63;
            t61 = qv(1).*2.0;
            t68 = qv(2).*qv(3).*t47.*2.0;
            t62 = t61-t68;
            t64 = P(3).*qv(2).*4.0;
            t65 = t(2).*t54;
            t66 = t(1).*t60;
            t90 = t(3).*qv(2).*4.0;
            t91 = P(2).*t54;
            t92 = P(1).*t60;
            t67 = t64+t65+t66-t90-t91-t92;
            t70 = t52+t69;
            t71 = t61+t68;
            t95 = t7.*t47.*2.0;
            t72 = t49-t95;
            t73 = P(1).*t62;
            t74 = P(2).*t70;
            t93 = t(1).*t62;
            t94 = t(2).*t70;
            t75 = t73+t74-t93-t94;
            t76 = 1.0./rhoy;
            t77 = t26.*v0;
            t78 = t(2).*t30;
            t79 = P(1).*t31;
            t80 = P(3).*t32;
            t83 = P(2).*t30;
            t84 = t(1).*t31;
            t85 = t(3).*t32;
            t81 = t78+t79+t80-t83-t84-t85;
            t86 = f.*t76.*t81;
            t82 = t77-t86;
            p = [t33.*t41;t33.*t82];
            if nargout > 1
                t96 = t13.*u0;
                t97 = t96-f.*t17.*t34;
                t98 = t33.*t97;
                t99 = t15.*u0;
                t100 = f.*t20.*t34;
                t101 = t99+t100;
                t102 = t33.*t101;
                t103 = t6.*u0;
                t104 = t103-f.*t21.*t34;
                t105 = t6.*t41.*t45;
                t106 = t13.*v0;
                t107 = f.*t31.*t76;
                t108 = t106+t107;
                t109 = t33.*t108;
                t110 = t15.*v0;
                t111 = t110-f.*t30.*t76;
                t112 = t33.*t111;
                t113 = t6.*v0;
                t114 = t113-f.*t32.*t76;
                t115 = t6.*t45.*t82;
                JA = reshape([t98-t13.*t41.*t45,t109-t13.*t45.*t82,t102-t15.*t41.*t45,t112-t15.*t45.*t82,t105-t33.*t104,t115-t33.*t114,t33.*(t59.*u0-f.*t34.*(P(2).*t53+P(3).*t54-t(2).*t53-t(3).*t54))-t41.*t45.*t59,t33.*(t59.*v0+f.*t76.*(P(2).*qv(1).*4.0-P(3).*t50-P(1).*t70-t(2).*qv(1).*4.0+t(3).*t50+t(1).*t70))-t45.*t59.*t82,t33.*(t67.*u0+f.*t34.*(P(1).*qv(2).*4.0+P(3).*t60-P(2).*t62-t(1).*qv(2).*4.0-t(3).*t60+t(2).*t62))-t41.*t45.*t67,t33.*(t67.*v0-f.*t76.*(P(3).*t48+P(1).*t71-t(3).*t48-t(1).*t71))-t45.*t67.*t82,-t33.*(t75.*u0-f.*t34.*(P(1).*qv(3).*4.0-P(2).*t72-P(3).*t71-t(1).*qv(3).*4.0+t(2).*t72+t(3).*t71))+t41.*t45.*t75,-t33.*(t75.*v0-f.*t76.*(P(2).*qv(3).*4.0-P(3).*t53+P(1).*t72-t(2).*qv(3).*4.0+t(3).*t53-t(1).*t72))+t45.*t75.*t82],[2,6]);
            end
            if nargout > 2
                JB = reshape([-t98+t13.*t41.*t45,-t109+t13.*t45.*t82,-t102+t15.*t41.*t45,-t112+t15.*t45.*t82,-t105+t33.*t104,-t115+t33.*t114],[2,3]);
            end
        end
        
    end % methods
end % class
