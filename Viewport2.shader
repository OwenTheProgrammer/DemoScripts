Shader "OwenTheProgrammer/Viewport2" {
    Properties {
        _CameraPosition("Camera Position", Vector) = (0, 0, -1, 0)
        _CameraRotation("Camera Rotation", Vector) = (0, 0, 0, 0)
        _CameraFOV("Camera FOV", Range(1, 179)) = 60
    }
    SubShader {
        Pass {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            #define cot(x) ( cos(x) / sin(x) )

            struct inputData {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            v2f vert(inputData i) {
                v2f o;
                o.vertex = UnityObjectToClipPos(i.vertex);
                o.uv = i.uv;
                return o;
            }
            

            float3 _CameraPosition;
            float3 _CameraRotation;
            float _CameraFOV;

            struct Camera {
                float3 worldPos;
                float fovAngle;
                float fovSlope;

                float2 screenPos;
                float2 clipPos;
                
                float3x3 viewMatrix;
                
                float3 localRayDir;
                float3 worldRayDir;
            };

            struct DirectionalLight {
                float3 direction;
                float3 color;
            };

            struct Plane {
                float3 worldPos;
                float2 scale;
                float3 normal;
                
                float rayDistance;
                float3 worldRayPos;
                float3 localRayPos;

                float geometryMask;
                float3 albedo;
            };

            struct Box {
                float3 worldPos;
                float3 scale;

                float rayDistance;
                float3 worldRayPos;
                float3 localRayPos;

                float geometryMask;
                float3 normal;
                float3 albedo;
            };

            struct Sphere {
                float3 worldPos;
                float radius;

                float rayDistance;
                float3 worldRayPos;
                float3 localRayPos;
                
                float geometryMask;
                float3 normal;
                float3 albedo;
            };

            float4x4 RotationMatrix(float3 angles) {
                float3 angle_rad = radians(angles);
                float3 c = cos(angle_rad);
                float3 s = sin(angle_rad);

                float4x4 RX = {
                    1.0, 0.0,  0.0, 0.0,
                    0.0, c.x, -s.x, 0.0,
                    0.0, s.x,  c.x, 0.0,
                    0.0, 0.0,  0.0, 1.0
                };
                float4x4 RY = {
                     c.y, 0.0, s.y, 0.0,
                     0.0, 1.0, 0.0, 0.0,
                    -s.y, 0.0, c.y, 0.0,
                     0.0, 0.0, 0.0, 1.0
                };
                float4x4 RZ = {
                    c.z, -s.z, 0.0, 0.0,
                    s.z,  c.z, 0.0, 0.0,
                    0.0,  0.0, 1.0, 0.0,
                    0.0,  0.0, 0.0, 1.0
                };
                return mul(RY, mul(RX, RZ));
            }


            //Projects a direction vector from the camera position through the unit distance clipping plane
            float3 GetCameraRayDirection(float2 clipPos, float fovSlope) {
                //Scale [-1 | +1] range to [-viewAngle | +viewAngle]
                float3 viewPlane = float3(clipPos * fovSlope, 1);
                return normalize(viewPlane);
            }

            float3x3 GetCameraLookAtMatrix(float3 camPos, float3 targetPos) {
                float3 fwd = normalize(camPos - targetPos);
                float3 right = cross(fwd, float3(0, 1, 0));
                float3 up = cross(right, fwd);
                return transpose(float3x3(normalize(right), normalize(up), -fwd));
            }

            float3 Skybox(float3 rayDir, DirectionalLight light) {
                //return max(0.0, dot(rayDir, light.direction)) * 0.7 + 0.04;
                return max(0, rayDir.y) * 0.7 + 0.04;
            }

            float3 PlaneMaterial(float2 uv) {
                float2 terms = step(frac(uv), 0.5);
                float checkers = abs(terms.x - abs(terms.y)); //xor
                return lerp(0.2, 0.4, checkers);
            }

            float3 SphereMaterial(Sphere sphere, DirectionalLight light) {
                float NdotL = max(0.0, dot(sphere.normal, light.direction));
                return max(0.1, NdotL * light.color);
            }

            Camera CreateCamera(float2 uv) {
                Camera camera = (Camera)0;
                camera.worldPos = _CameraPosition;
                //comment out for no more rotation
                camera.worldPos.xz = 3 * float2(cos(_Time.y * 0.5), sin(_Time.y * 0.5));
                camera.fovAngle = radians(_CameraFOV * 0.5);
                camera.fovSlope = tan(camera.fovAngle);
                
                camera.screenPos = uv;
                camera.clipPos = camera.screenPos * 2 - 1;

                camera.viewMatrix = GetCameraLookAtMatrix(camera.worldPos, float3(0,0,0));
                //camera.viewMatrix = (float3x3)RotationMatrix(_CameraRotation);

                camera.localRayDir = GetCameraRayDirection(camera.clipPos, camera.fovSlope);
                camera.worldRayDir = mul(camera.viewMatrix, camera.localRayDir);

                return camera;
            }

            void CalculatePlaneInfo(Camera cam, inout Plane p) {
                //Ray to plane formula
                float t_n = dot(p.worldPos - cam.worldPos, p.normal);
                float t_d = dot(cam.worldRayDir, p.normal);
                float t = t_n / t_d;

                //Calculate ray position in different spaces
                p.rayDistance = t;
                p.worldRayPos = cam.worldPos + cam.worldRayDir * t;
                p.localRayPos = p.worldRayPos - p.worldPos;
                
                //Geometry masking
                float isFrontface = t_d < 1e-6;
                float isInBounds = all(abs(p.localRayPos.xz) < (p.scale * 0.5));
                
                p.geometryMask = isFrontface && isInBounds;
                p.albedo = PlaneMaterial(p.localRayPos.xz);
            }

            void CalculateSphereInfo(Camera cam, DirectionalLight light, inout Sphere sphere) {
                float3 localRay = sphere.worldPos - cam.worldPos;
                float tn = dot(localRay, cam.worldRayDir);
                //if(tn < 0) no hit
                float sdf = dot(localRay, localRay) - tn * tn;
                //if(sdf > tn*tn) no hit
                float hitDist = sqrt(sphere.radius * sphere.radius - sdf);
                float t = tn - hitDist;

                //Calculate ray position in different spaces
                sphere.rayDistance = t;
                sphere.worldRayPos = cam.worldPos + cam.worldRayDir * t;
                sphere.localRayPos = sphere.worldRayPos - sphere.worldPos;

                //Geometry masking
                sphere.geometryMask = (tn > 0) && (sdf < sphere.radius * sphere.radius);
                sphere.normal = sphere.localRayPos / sphere.radius;
                //sphere.normal = sdf; //sphere.localRayPos / sphere.radius;
                sphere.albedo = SphereMaterial(sphere, light);
            }

            void CalculateBoxInfo(Camera cam, inout Box box) {
                float3 invRayDir = rcp(cam.worldRayDir);
                float3 camTangent = invRayDir * (cam.worldPos - box.worldPos);
                float3 quadrant = abs(invRayDir) * (box.scale * 0.5);

                float3 t1 = -camTangent - quadrant;
                float3 t2 = -camTangent + quadrant;

                float tNear = max(t1.x, max(t1.y, t1.z));
                float tFar = min(t2.x, min(t2.y, t2.z));


                //Calculate ray positionin different spaces
                box.rayDistance = tNear;
                box.worldRayPos = cam.worldPos + cam.worldRayDir * tNear;
                box.localRayPos = box.worldRayPos - box.worldPos;

                float isInBounds = (tNear <= tFar && tFar > 0.0);

                box.geometryMask = isInBounds;
                //box.normal = -sign(cam.worldRayDir) * step(t1.yzx, t1.xyz) * step(t1.zxy, t1.xyz);
                box.normal = step(t1.yzx, t1.xyz) * step(t1.zxy, t1.xyz);
                box.albedo = box.normal;
            }

            float Shadow(Plane plane, DirectionalLight light, Sphere sphere) {
                float3 rayHit = plane.worldRayPos;
                float3 ballPivot = sphere.worldPos;
                float3 lightDir = light.direction;

                float shadowPlaneDist = dot(ballPivot - rayHit, lightDir) / dot(lightDir, lightDir);
                float3 shadowPlaneHit = rayHit + shadowPlaneDist * lightDir;
                float3 localPlanePos = shadowPlaneHit - ballPivot;

                return saturate(distance(rayHit, ballPivot) - sphere.radius);
            }


            float3 frag (v2f i) : SV_Target {
                
                DirectionalLight light = (DirectionalLight)0;
                light.direction = normalize(_WorldSpaceLightPos0);
                light.color = float3(1,1,1);
                
                Camera camera = CreateCamera(i.uv);
                
                Plane groundPlane = (Plane)0;
                groundPlane.worldPos = float3(0,-0.5,0);
                groundPlane.scale = float2(4, 4);
                groundPlane.normal = float3(0,1,0);

                Sphere ball = (Sphere)0;
                ball.worldPos = float3(0, 0, 0);
                ball.worldPos = float3(0, sin(_Time.y) * 0.5 + 0.5, 0);
                ball.radius = 0.5;

                Box cube = (Box)0;
                cube.worldPos = float3(0, 1, 0);
                cube.scale = float3(1, 1, 1);


                CalculatePlaneInfo(camera, groundPlane);
                float3 groundColor = groundPlane.albedo * groundPlane.geometryMask;

                CalculateBoxInfo(camera, cube);
                float3 boxColor = cube.albedo * cube.geometryMask;

                CalculateSphereInfo(camera, light, ball);
                float3 sphereColor = ball.normal * ball.geometryMask;

                float ballShadow = Shadow(groundPlane, light, ball);

                float3 frameBuffer = Skybox(camera.worldRayDir, light);
                frameBuffer *= (1 - groundPlane.geometryMask);
                //frameBuffer += groundColor;
                frameBuffer += groundColor * ballShadow;
                
                frameBuffer *= (1 - ball.geometryMask);
                frameBuffer += saturate(sphereColor);

                //frameBuffer *= (1 - cube.geometryMask);
                //frameBuffer += saturate(boxColor);

                
                
                //frameBuffer = lerp(frameBuffer, groundColor, groundPlane.geometryMask);
                //frameBuffer = (1 - ball.geometryMask) * frameBuffer;

                //return sphereColor + frameBuffer;
                return frameBuffer;
            }
            ENDCG
        }
    }
}
