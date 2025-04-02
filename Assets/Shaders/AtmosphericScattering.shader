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
			HLSLPROGRAM
			#pragma enable_d3d11_debug_symbols
			#pragma vertex vert
			#pragma fragment frag
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "include/AtmosphericScattering.hlsl"
			TEXTURE2D(_TransmittanceLUT);
            SAMPLER(sampler_TransmittanceLUT);
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
				float dist = DistanceToDualSphere(startWorldPos.y + params.PlanetRadius, dir, params.PlanetRadius, params.PlanetRadius + params.AtmosphereHeight);
				const int N_SAMPLES = 32;
			    float stepLen = dist / N_SAMPLES;
				float3 step = stepLen * dir;
				float3 p = startWorldPos.xyz + step * 0.5;
				float height;
				float3 extinction, t2, t1,s;
				float3 color = float3(0, 0, 0);
				p.y += params.PlanetRadius;
				[unroll]
				for (int i = 0; i < N_SAMPLES; i++)
				{
					height = length(p) - params.PlanetRadius;
					extinction = RayleighScatteringCoefficient(height, params) + MieScatteringCoefficient(height, params) +
									OzoneAbsorption(height, params) + MieAbsorption(height, params);
					t1 = 1;//TransmittanceByLUT(p, _LightDir.xyz, params, _TransmittanceLUT, sampler_TransmittanceLUT);
					s = Scatter(height, _LightDir.xyz, -dir, params);
					t2 = 1;//exp(-extinction * stepLen);

					color += t1 * s * t2 * stepLen * _LightColor;
					p += step;
			
				}
				// // 从屏幕空间到视图空间的转换（可选，取决于具体需求）
				// float depth = tex2D(_CameraDepthTexture, i.uv).r; // 获取深度值
				// float4 viewPos = float4(i.screenPos.xyz, depth); // 构建视图空间位置
				// viewPos = mul(UNITY_MATRIX_I_VP, viewPos); // 从屏幕空间到视图空间
				//
				// // 从视图空间到世界空间
				// float3 worldPos = mul(unity_WorldToObject, viewPos).xyz; // 从视图空间转换回世界空间（注意这里是反向矩阵）
				// worldPos = mul(unity_ObjectToWorld, float4(worldPos, 1.0)).xyz; // 如果需要，再次转换回正确的世界空间（通常不必要）
				//
				// // 使用worldPos进行计算...
				// return float4(worldPos, 1.0); // 示例返回一个颜色，实际应用中根据需要返回不同的值
				return float4(color, 1);
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
