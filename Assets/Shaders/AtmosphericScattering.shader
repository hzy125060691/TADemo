Shader "HZY/AtmosphericScattering"
{
   Properties
	{
	}
	SubShader
	{
		Tags
		{
			"RenderType"="Opaque"
			"RenderPipeline"="UniversalPipeline"
            "IgnoreProjector" = "True"
		}
		Pass
		{
			Name "Scattering"
			Tags
			{
				"LightMode" = "Scattering"
			}
			
			Blend One Zero
			HLSLPROGRAM
			#pragma enable_d3d11_debug_symbols
			#pragma vertex vert
			#pragma fragment frag
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "include/AtmosphericScattering.hlsl"
			TEXTURE2D(_TransmittanceLUT);
            SAMPLER(sampler_TransmittanceLUT);
			TEXTURE2D(_DepthRT);
            SAMPLER(sampler_DepthRT);
			CBUFFER_START(UnityPerMaterial)
				float4 _ScatteringParams;
				float4 _PlanetParams;
				float4 _LightColor;
				float4 _LightDir;
				float4x4 _ReverseVPMatrix;
				//float4 _ScatteringST;
			CBUFFER_END

			struct appdate
			{
				float4 positionOS: POSITION;
				float2 uv: TEXCOORD0;
			};

			struct v2f
			{
				float4 positionCS: SV_POSITION;
				float2 uv: TEXCOORD0;
			};

			v2f vert(appdate v)
			{
				v2f o;
				o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
				o.uv = v.uv;
				return o;
			}
			half4 frag(v2f i): SV_Target
			{
				AtmosphereParameter params = FillAtmosphereParameter(_ScatteringParams, _PlanetParams);
				
#if UNITY_UV_STARTS_AT_TOP
				float2 uv = (i.uv - 0.5) * 2;
#else

#endif
				
				float4 endWorldPos = mul(_ReverseVPMatrix, float4(uv, 1, 1));
				endWorldPos /= endWorldPos.w;
				float4 startWorldPos = mul(_ReverseVPMatrix, float4(uv, -1, 1));
				startWorldPos /= startWorldPos.w;
				float3 es = endWorldPos.xyz - startWorldPos.xyz;
				float3 dir = normalize(es);
			    //float dist = length(es);
			    //float dist = DistanceToSphere(startWorldPos.y + params.PlanetRadius, dir, params.PlanetRadius + params.AtmosphereHeight);
				//float4 depth = SAMPLE_TEXTURE2D(_DepthRT, sampler_DepthRT, i.uv);

				
				float dist = DistanceToDualSphere(startWorldPos.y + params.PlanetRadius, dir, params.PlanetRadius, params.PlanetRadius + params.AtmosphereHeight);
				float depth = SAMPLE_DEPTH_TEXTURE(_DepthRT, sampler_DepthRT, i.uv);
				depth = Linear01DepthFromNear(depth, _ZBufferParams) * 2- 1;
				if (depth < 1)
				{
					float4 depthPos = mul(_ReverseVPMatrix, float4(uv, depth.x, 1));
					depthPos /= depthPos.w;
					float maxLength = length(depthPos - startWorldPos);
					dist = min(dist, maxLength);
				}
				const int N_SAMPLES = 32;
			    float stepLen = dist / N_SAMPLES;
				float3 step = stepLen * dir;
				float3 p = startWorldPos.xyz + step * 0.5;
				float height;
				float3 extinction, t2, t1,s;
				float3 color = float3(0, 0, 0);
				p.y += params.PlanetRadius;
				[unroll]
				for (int ii = 0; ii < N_SAMPLES; ii++)
				{
					height = length(p) - params.PlanetRadius;
					extinction = RayleighScatteringCoefficient(height, params) + MieScatteringCoefficient(height, params) +
									OzoneAbsorption(height, params) + MieAbsorption(height, params);
					t1 = TransmittanceByLUT(height, -_LightDir.xyz, params, _TransmittanceLUT, sampler_TransmittanceLUT);
					s = Scatter(height, _LightDir.xyz, -dir, params);
					t2 = exp(-extinction * stepLen);

					color += t1 * s * t2 * stepLen * _LightColor;
					p += step;
			
				}
				return float4((color), 1);
			}
			ENDHLSL
		}
		Pass
		{
			Name "TransmittanceLUT"
			Tags
			{
				"LightMode" = "TransmittanceLUT"
			}
			HLSLPROGRAM
			#pragma enable_d3d11_debug_symbols
			#pragma vertex vert
			#pragma fragment frag
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "include/AtmosphericScattering.hlsl"

			CBUFFER_START(UnityPerMaterial)
				float4 _ScatteringParams;
				float4 _PlanetParams;
			CBUFFER_END

			struct appdate
			{
				float4 positionOS: POSITION;
				float2 uv: TEXCOORD0;
			};

			struct v2f
			{
				float4 positionCS: SV_POSITION;
				float2 uv: TEXCOORD0;
			};

			v2f vert(appdate v)
			{
				v2f o;
				o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
				o.uv = v.uv;
				return o;
			}

			half4 frag(v2f i): SV_Target
			{
				AtmosphereParameter params = FillAtmosphereParameter(_ScatteringParams, _PlanetParams);
				float3 hcd = UV2TransmittanceHC(i.uv, params.PlanetRadius, params.PlanetRadius + params.AtmosphereHeight);
				float height = hcd.y;
				float cosTheta = hcd.x;
				float dist = hcd.z;
				float3 ret = Transmit(float3(0, height, 0), float3(sqrt(1 - cosTheta * cosTheta), cosTheta, 0) * dist, params);
				return half4(ret, 1);
			}
			ENDHLSL
		}
		Pass
		{
			Name "BlendScattering"
			Tags
			{
				"LightMode" = "BlendScattering"
			}
			Blend One One
			
			HLSLPROGRAM
			#pragma enable_d3d11_debug_symbols
			#pragma vertex vert
			#pragma fragment frag
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "include/AtmosphericScattering.hlsl"
			TEXTURE2D(_ScatteringRT);
            SAMPLER(sampler_ScatteringRT);
			CBUFFER_START(UnityPerMaterial)
			CBUFFER_END

			struct appdate
			{
				float4 positionOS: POSITION;
				float2 uv: TEXCOORD0;
			};

			struct v2f
			{
				float4 positionCS: SV_POSITION;
				float2 uv: TEXCOORD0;
			};

			v2f vert(appdate v)
			{
				v2f o;
				o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
				//o.uv = v.uv;
				o.uv = float2(v.uv.x, 1-v.uv.y);
				return o;
			}

			half4 frag(v2f i): SV_Target
			{
				return SAMPLE_TEXTURE2D(_ScatteringRT, sampler_ScatteringRT, i.uv);
			}
			ENDHLSL
		}
	}
	
	Fallback Off
}
