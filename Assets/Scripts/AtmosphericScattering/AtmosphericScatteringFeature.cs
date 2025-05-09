using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;

public class AtmosphericScatteringFeature : ScriptableRendererFeature
{
    private class AtmosphericScatteringPass : ScriptableRenderPass
    {
        private static readonly int _ScatteringParams = Shader.PropertyToID("_ScatteringParams");
        private static readonly int _PlanetParams = Shader.PropertyToID("_PlanetParams");
        private static readonly int _LightColor = Shader.PropertyToID("_LightColor");
        private static readonly int _LightDir = Shader.PropertyToID("_LightDir");
        private static readonly int _ReverseVPMatrix = Shader.PropertyToID("_ReverseVPMatrix");
        private static readonly int _ScatteringST = Shader.PropertyToID("_ScatteringST");
        private static readonly int _TransmittanceLUT = Shader.PropertyToID("_TransmittanceLUT");
        private static readonly int _ScatteringRT = Shader.PropertyToID("_ScatteringRT");
        private static readonly int _DepthRT = Shader.PropertyToID("_DepthRT");
        private static readonly int _SceneRT = Shader.PropertyToID("_SceneRT");
        private static RenderTextureDescriptor Desc = new RenderTextureDescriptor()
        {
            msaaSamples = 1,
            sRGB = false,
            useMipMap = false,
            depthBufferBits = 0,
            volumeDepth = 1,
            dimension = UnityEngine.Rendering.TextureDimension.Tex2D,
            graphicsFormat = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.RGB111110Float, false),

        };
        private AtmosphereParameter Param;
        private AtmosphereParameter Last = new AtmosphereParameter();

        private static Mesh s_TriangleMesh;
        private static Shader AtmosphericScatteringShader;
        private const Int32 ScatteringPassIdx = 0;
        private const Int32 TransmittanceLUTPassIdx = 1;
        private const Int32 BlendPassIdx = 2;
        private static Material AtmosphericScatteringMaterial;
        public AtmosphericScatteringPass(AtmosphereParameter param)
        {
            renderPassEvent = RenderPassEvent.AfterRenderingSkybox;
            Param = param;
            Last.AtmosphereHeight = -1;
            if (!s_TriangleMesh)
            {
                var nearClipZ = -1f;
                if (SystemInfo.usesReversedZBuffer)
                    nearClipZ = 1f;
                
                var vertices = new Vector3[3];
                var uvs = new Vector2[3];
                Vector2 uv;
                for (int i = 0; i < 3; i++)
                {
                    uv = new Vector2((i << 1) & 2, i & 2);
                    vertices[i] = new Vector3(uv.x * 2.0f - 1.0f, uv.y * 2.0f - 1.0f, nearClipZ);
                    
                    if (SystemInfo.graphicsUVStartsAtTop)
                        uvs[i] = new Vector2((i << 1) & 2, 1.0f - (i & 2));
                    else
                        uvs[i] = new Vector2((i << 1) & 2, i & 2);
                }
                s_TriangleMesh = new Mesh();
                s_TriangleMesh.vertices = vertices;
                s_TriangleMesh.uv = uvs;
                s_TriangleMesh.triangles = new int[3] { 1, 0, 2 };

                

            }

            if (!AtmosphericScatteringShader)
            {
                AtmosphericScatteringShader = Shader.Find("HZY/AtmosphericScattering");
            }

            if (!AtmosphericScatteringMaterial)
            {
                AtmosphericScatteringMaterial = new Material(AtmosphericScatteringShader);
            }
            //if (Param.TransmittanceLUT == null)
            var size = GetGameSize();
            {
                Desc.width = 512;
                Desc.height = 512;
                Param.TransmittanceLUT = new RenderTexture(Desc)
                {
                    filterMode = FilterMode.Bilinear,
                    wrapMode = TextureWrapMode.Clamp,
                };
                Param.TransmittanceLUT.name = "TransmittanceLUT";
                Param.TransmittanceLUT.Create();
            }
            {
                Desc.width = (Int32)size.x;
                Desc.height = (Int32)size.y;
                Param.ScatteringRT = new RenderTexture(Desc)
                {
                    filterMode = FilterMode.Bilinear,
                    wrapMode = TextureWrapMode.Clamp,
                };;
                Param.ScatteringRT.name = "ScatteringRT";
                Param.ScatteringRT.Create();
                
            }
        }

        ~AtmosphericScatteringPass()
        {
            if (Param.TransmittanceLUT)
            {
                Param.TransmittanceLUT.Release();
                Param.TransmittanceLUT = null;
            }
        }
        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            base.Configure(cmd, cameraTextureDescriptor);
            Target = new RenderTargetIdentifier(BuiltinRenderTextureType.CurrentActive);
        }

        private RenderTargetIdentifier Target;
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            base.OnCameraSetup(cmd, ref renderingData);
            //Target = renderingData.cameraData.camera.targetTexture;
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            // var cmd = renderingData.commandBuffer;
            CommandBuffer cmd = CommandBufferPool.Get("AtmosphericScattering");
            Boolean exe = false;
            exe |= GenerateTransmittranceLUT(cmd);
            exe |= Scattering(cmd, ref renderingData);
            if (exe)
            {
                Blend(cmd, ref renderingData);
                context.ExecuteCommandBuffer(cmd);
            }
            CommandBufferPool.Release(cmd);
        }

        private void Blend(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var target = renderingData.cameraData.renderer.cameraColorTargetHandle;
            cmd.SetRenderTarget( target, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.DontCare,
                target, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.DontCare);
            if (!SystemInfo.usesReversedZBuffer)
            {
                cmd.SetProjectionMatrix(Matrix4x4.Ortho(-1, 1, -1, 1, -1,1));
            }
            else
            {
                cmd.SetProjectionMatrix(Matrix4x4.Ortho(-1, 1, -1, 1, -1,1));
            }

            if (SystemInfo.graphicsUVStartsAtTop)
            {
                
            }
            AtmosphericScatteringMaterial.SetTexture(_ScatteringRT, Param.ScatteringRT);
            cmd.SetViewMatrix(Matrix4x4.identity);
            cmd.DrawMesh(s_TriangleMesh, Matrix4x4.identity, AtmosphericScatteringMaterial, 0, BlendPassIdx);
        }
        
        private Boolean GenerateTransmittranceLUT(CommandBuffer cmd)
        {
            // if (Last.IsEqual(Param))
            // {
            //     return false;
            // }
            //Debug.LogError("GenerateTransmittranceLUT");
            Last.CopyFrom(Param);
            cmd.SetRenderTarget(Param.TransmittanceLUT, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.DontCare,
                Param.TransmittanceLUT, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.DontCare);
            if (!SystemInfo.usesReversedZBuffer)
            {
                cmd.SetProjectionMatrix(Matrix4x4.Ortho(-1, 1, -1, 1, -1,1));
            }
            else
            {
                cmd.SetProjectionMatrix(Matrix4x4.Ortho(-1, 1, -1, 1, -1,1));
            }
            AtmosphericScatteringMaterial.SetVector(_ScatteringParams, 
                new Vector4(
                    Param.RayleighScalarHeight,
                    Param.MieScalarHeight,
                    Param.MieAnisotropy));
            AtmosphericScatteringMaterial.SetVector(_PlanetParams, 
                new Vector4(
                    Param.PlanetRadius,
                    Param.AtmosphereHeight,
                    Param.OzoneCenterHeight,
                    Param.OzoneWidth
                    ));
            cmd.SetViewMatrix(Matrix4x4.identity);
            //cmd.ClearRenderTarget(RTClearFlags.All, Color.black, 0, 0);
            cmd.DrawMesh(s_TriangleMesh, Matrix4x4.identity, AtmosphericScatteringMaterial, 0, TransmittanceLUTPassIdx);
            return true;
        }

        private Boolean Scattering(CommandBuffer cmd, ref RenderingData renderingData)
        {
            Camera cam = renderingData.cameraData.camera;
            cmd.SetRenderTarget(Param.ScatteringRT, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.DontCare,
                Param.ScatteringRT, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.DontCare);
            if (!SystemInfo.usesReversedZBuffer)
            {
                cmd.SetProjectionMatrix(Matrix4x4.Ortho(-1, 1, -1, 1, -1,1));
            }
            else
            {
                cmd.SetProjectionMatrix(Matrix4x4.Ortho(-1, 1, -1, 1, -1,1));
            }
            AtmosphericScatteringMaterial.SetVector(_ScatteringParams, 
                new Vector4(
                    Param.RayleighScalarHeight,
                    Param.MieScalarHeight,
                    Param.MieAnisotropy));
            AtmosphericScatteringMaterial.SetVector(_PlanetParams, 
                new Vector4(
                    Param.PlanetRadius,
                    Param.AtmosphereHeight,
                    Param.OzoneCenterHeight,
                    Param.OzoneWidth
                ));
            var light = GameObject.FindObjectOfType<Light>();
            AtmosphericScatteringMaterial.SetVector(_LightColor, 
                light.color * light.intensity);
            AtmosphericScatteringMaterial.SetVector(_LightDir, 
                light.transform.forward);
            AtmosphericScatteringMaterial.SetMatrix(_ReverseVPMatrix, (cam.projectionMatrix * cam.worldToCameraMatrix).inverse);
            AtmosphericScatteringMaterial.SetVector(_ScatteringST, 
                new Vector4(
                    Screen.width, Screen.height, 1f / Screen.width, 1f / Screen.height));
            AtmosphericScatteringMaterial.SetTexture(_TransmittanceLUT, Param.TransmittanceLUT);
            AtmosphericScatteringMaterial.SetTexture(_DepthRT, renderingData.cameraData.renderer.cameraDepthTargetHandle);
            AtmosphericScatteringMaterial.SetTexture(_SceneRT, renderingData.cameraData.renderer.cameraColorTargetHandle);
            cmd.SetViewMatrix(Matrix4x4.identity);
            //cmd.ClearRenderTarget(RTClearFlags.All, Color.black, 0, 0);
            cmd.DrawMesh(s_TriangleMesh, Matrix4x4.identity, AtmosphericScatteringMaterial, 0, ScatteringPassIdx);
            return true;
        }
        
    }
    [Serializable]
    public class AtmosphereParameter
    {
        [SerializeField]
        [Tooltip("瑞利散射的标高")]
        public Single RayleighScalarHeight = 8500;//瑞利散射的标高
        [SerializeField]
        [Tooltip("米氏散射的标高")]
        public Single MieScalarHeight = 1200;//米氏散射的标高
        [SerializeField]
        [Tooltip("控制米氏散射波瓣的各向异性参数")]
        [Range(-0.999f, .999f)]
        public Single MieAnisotropy = 0.99f;//控制米氏散射波瓣的各向异性参数
        [SerializeField]
        [Tooltip("行星半径")]
        public Single PlanetRadius = 6000000;//行星半径
        [SerializeField]
        [Tooltip("臭氧层中心高度")]
        public Single OzoneCenterHeight = 25000;//臭氧层中心高度
        [SerializeField]
        [Tooltip("臭氧层宽度")]
        public Single OzoneWidth = 15000;//臭氧层宽度
        [SerializeField]
        [Tooltip("大气层厚度")]
        public Single AtmosphereHeight = 50000;//大气层厚度
        [Tooltip("透射的LUT,展示用，给值也没用")]
        public RenderTexture TransmittanceLUT;
        [Tooltip("展示大气散射结果,展示用，给值也没用")]
        public RenderTexture ScatteringRT;
        public void CopyFrom(AtmosphereParameter other)
        {
            this.RayleighScalarHeight = other.RayleighScalarHeight;
            this.MieScalarHeight = other.MieScalarHeight;
            this.MieAnisotropy = other.MieAnisotropy;
            this.PlanetRadius = other.PlanetRadius;
            this.OzoneCenterHeight = other.OzoneCenterHeight;
            this.OzoneWidth = other.OzoneWidth;
            this.AtmosphereHeight = other.AtmosphereHeight;
        }
        public void CopyTo(AtmosphereParameter other)
        {
            other.CopyFrom(this);
        }
        public Boolean IsEqual(AtmosphereParameter other)
        {
            return this.RayleighScalarHeight == other.RayleighScalarHeight &&
                   this.MieScalarHeight == other.MieScalarHeight &&
                   this.MieAnisotropy == other.MieAnisotropy &&
                   this.PlanetRadius == other.PlanetRadius &&
                   this.OzoneCenterHeight == other.OzoneCenterHeight &&
                   this.OzoneWidth == other.OzoneWidth &&
                   this.AtmosphereHeight == other.AtmosphereHeight;
        }
    };
    [SerializeField]
    [Tooltip("大气与行星的一些参数")]
    private AtmosphereParameter Parameter = new AtmosphereParameter();
    
    private AtmosphericScatteringPass ScatteringPass;
    public override void Create()
    {
        ScatteringPass = new AtmosphericScatteringPass(Parameter);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (renderingData.cameraData.cameraType != CameraType.Game)
        {
            return;
        }
        renderer.EnqueuePass(ScatteringPass);
    }

    private static Vector2 GetGameSize()
    {
        var mouseOverWindow = UnityEditor.EditorWindow.mouseOverWindow;
        System.Reflection.Assembly assembly = typeof(UnityEditor.EditorWindow).Assembly;
        System.Type type = assembly.GetType("UnityEditor.PlayModeView");

        Vector2 size = (Vector2) type.GetMethod(
            "GetMainPlayModeViewTargetSize",
            System.Reflection.BindingFlags.NonPublic |
            System.Reflection.BindingFlags.Static
        ).Invoke(mouseOverWindow, null);
        return size;
    }
}
