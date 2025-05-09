#ifndef ATMOSPHERICSCATTERING
#define ATMOSPHERICSCATTERING
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Macros.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "./CustomMath.hlsl"
/// 大气参数
struct AtmosphereParameter
{
    float RayleighScalarHeight;// = 8500;//瑞利散射的标高
    float MieScalarHeight;// = 1200;//米氏散射的标高
    float MieAnisotropy;// = 1;//控制米氏散射波瓣的各向异性参数
    float PlanetRadius;// = 10000;//行星半径
    float OzoneCenterHeight;// = 25000;//臭氧层中心高度
    float OzoneWidth;// = 15000;//臭氧层宽度
    float AtmosphereHeight;// = 50000;//大气层厚度
};
/// 瑞利散射 散射系数
/// @param height 海拔高度
/// @param params 大气参数
/// @return 散射系数
inline float3 RayleighScatteringCoefficient(float height, in AtmosphereParameter params)
{
    const float3 sigma = float3(5.802, 13.558, 33.1) * 1e-6 ;//水平面的散射系数
    return sigma * exp(-height / params.RayleighScalarHeight);//高度衰减
}
/// 瑞利散射相位函数
/// @param cosTheta 入射到散射方向的角度的cos值
/// @return 
inline float RayleighPhase(float cosTheta)
{
    const float tmp =  3.0 / (16.0 * PI);
    return (1 + cosTheta * cosTheta) * tmp;
}
/// 米氏散射 散射系数
/// @param height 海拔高度
/// @param params 大气参数
/// @return 散射系数
inline float3 MieScatteringCoefficient(float height, in AtmosphereParameter params)
{
    const float3 sigma = float3(3.996,3.996,3.996) * 1e-6;//水平面的散射系数
    return sigma * exp( - height / params.MieScalarHeight);//高度衰减

}
/// 米氏散射相位函数
/// @param cosTheta 入射到散射方向的角度的cos值
/// @return 
inline float MiePhase(float cosTheta, in AtmosphereParameter params)
{
    const float tmp =  3.0 / (8.0 * PI);
    float g = params.MieAnisotropy;
    float g2 = g * g;

    float ret = tmp * (1 - g2) * (1 + cosTheta * cosTheta)/ ((2 + g2) * (1 + g2 - 2 * g * cosTheta));
    float test =  (1 - g2) / ((2 + g2) * (1 + g2 - 2 * g * cosTheta));
    bool nan = (asuint(test) & 0x7fffffff) > 0x7f800000;
    if (nan)
    {
        return 111111111;
    }
    return ret;
}

/// 散射
/// @param height 海拔高度
/// @param inDir 入射方向
/// @param outDir 散射方向
/// @param params 大气参数
/// @return 
inline float3 Scatter(float height, float3 inDir, float3 outDir, in AtmosphereParameter params)
{
    float cosTheta = dot(inDir, outDir);
    float h = height;
    float3 rayleigh = RayleighScatteringCoefficient(h, params);
    rayleigh *=  RayleighPhase(cosTheta);
    float3 mie = MieScatteringCoefficient(h, params);
    mie *= MiePhase(cosTheta, params);
    return rayleigh + mie;
}

/// 米氏散射吸收
/// @param height 海拔高度
/// @param params 大气参数
/// @return 
inline float3 MieAbsorption(float height, in AtmosphereParameter params)
{
    const float3 sigma = float3(4.4, 4.4, 4.4) * 1e-6;//水平面的吸收参数
    return sigma * exp( - height / params.MieScalarHeight);//高度衰减
}
/// 臭氧层吸收
/// @param height 海拔高度
/// @param params 大气参数
/// @return 
inline float3 OzoneAbsorption(float height, in AtmosphereParameter params)
{
    const float3 sigma = float3(0.65, 1.881, 0.085) * 1e-6;//水平面的吸收参数
    float attenuation = max(0, 1 - abs(height - params.OzoneCenterHeight)/params.OzoneWidth);
    return sigma * attenuation;
}

/// 透射
/// @param start 起始点
/// @param end 结束点
/// @param params 大气参数
/// @return 
inline float3 Transmit(float3 start, float3 end, in AtmosphereParameter params)
{
    const int N_SAMPLES = 32;
    float3 es = end - start;
    float3 dir = normalize(es);
    float dist = length(es);
    float stepLen = dist / N_SAMPLES;
    float3 sum = 0;
    float3 step = stepLen * dir;
    float3 p = start + step * 0.5;
    float h;
    float3 scattering, absorption;
    [unroll]
    for (int i = 0; i < N_SAMPLES; i++)
    {
        h = p.y;//+ params.PlanetRadius;
        scattering = RayleighScatteringCoefficient(h, params) + MieScatteringCoefficient(h, params);
        absorption = OzoneAbsorption(h, params) + MieAbsorption(h, params);
        sum += (scattering + absorption) * stepLen;
        p += step;
    }
    return exp(-sum);
}

/// Ray March的单次散射计算
/// @param worldPos 起始坐标
/// @param viewDir 观察方向
/// @param lightDir 方向光方向
/// @param lightIntensity 光照强度
/// @param params 大气参数
/// @return 
// inline float3 RayMarchScattering(float3 worldPos, float3 viewDir, float3 lightDir, float lightIntensity, in AtmosphereParameter params)
// {
//     const int N_SAMPLES = 32;
//     float atmosphereRadius = params.PlanetRadius + params.AtmosphereHeight;
//     float dist = DistanceToSphere(worldPos.y + params.PlanetRadius, viewDir, atmosphereRadius);
//     float stepLen = dist / N_SAMPLES;
//     float3 step = stepLen * viewDir;
//     float3 lightRayMarchDir = -normalize(lightDir);
//     float tmpDist;
//     float3 end;
//     float3 p = worldPos + step * viewDir;
//     float3 color = float3(0, 0, 0);
//     [unroll]
//     for (int i = 0; i < N_SAMPLES; i++)
//     {
//         tmpDist = DistanceToSphere(p.y, lightRayMarchDir, atmosphereRadius);
//         end = p + lightRayMarchDir * tmpDist;
//         color += Transmit(p, end, params) * Scatter(p, lightRayMarchDir, viewDir, params) * Transmit(p, worldPos, params) * step * lightIntensity;
//
//         p += step * viewDir;
//     }
//     return color;
// }

/// 透射 海拔和天顶角的cos值进行0到1重映射
/// @param height 海拔高度
/// @param cosTheta 天顶角的余弦
/// @param radius0 行星半径
/// @param radius1 （大气层+行星）半径
/// @return 
inline float2 RemapTransmittanceUV(float height, float cosTheta, float radius0, float radius1)
{
    float radius = height + radius0;
    float r_2 = radius * radius;
    /// 这里把海拔对应的点到大气层形成的球体的表面的最近距离映射到0和最远距离映射到1
    /// 但是这里不直接除大气层的厚度，先吧海拔转变成路过该点(A)的0海拔球的切线的切点(B)与该点(A)的线段长度，把这个长度进行最大最小值的01映射
    float r0_2 = radius0 * radius0;
    float curH = sqrt(r_2 - r0_2);
    float maxH = sqrt(radius1 * radius1 - r0_2);
    
    /// 这里把天顶角COS值映射
    /// 当前海拔下，该点(A)向所有方向发射线，只取能扫到大气层边缘的部分，被遮挡的部分都抛弃
    /// 把最短的线段和最长的线段做线性映射到 01
    float dMin = radius1 - radius;
    float dMax = curH + maxH;
    float curDist = DistanceToSphereByCos(radius, cosTheta, radius1);
    return float2((curDist - dMin) / (dMax - dMin), curH / maxH);
}
/// UV重新映射到height和cos
/// 参考RemapTransmittanceUV的逆运算
/// @param uv 
/// @param radius0 行星半径
/// @param radius1 （大气层+行星）半径
/// @return (海拔高度,天顶角的余弦,当前角度到达大气层或者地面的距离)
inline float3 UV2TransmittanceHC(float2 uv, float radius0, float radius1)
{
    float r0_2 = radius0 * radius0;
    float maxH = sqrt(radius1 * radius1 - r0_2);
    float curH = uv.y * maxH;
    float radius = sqrt(curH * curH + r0_2);
    float height = radius - radius0;
    float min = radius1 - radius;
    float max = curH + maxH;
    float curDist = uv.x * (max - min) + min;
    float cos = DistToCos(curDist, radius, radius1);
    return float3(cos, height, curH);
}
inline AtmosphereParameter FillAtmosphereParameter(float4 scatteringParams, float4 planetParams)
{
    AtmosphereParameter ret;
    ret.RayleighScalarHeight = scatteringParams.x;
    ret.MieScalarHeight = scatteringParams.y;
    ret.MieAnisotropy = scatteringParams.z;
    ret.PlanetRadius = planetParams.x;
    ret.AtmosphereHeight = planetParams.y;
    ret.OzoneCenterHeight = planetParams.z;
    ret.OzoneWidth = planetParams.w;
    return ret;
}

/// 
/// @param height 海拔高度
/// @param dir 
/// @param params 
/// @param lut 
/// @param samplerLUT 
/// @return 
inline float3 TransmittanceByLUT(float height, float3 dir, in AtmosphereParameter params,
                                 TEXTURE2D(lut), SAMPLER(samplerLUT))
{
    float radius1 = params.PlanetRadius + params.AtmosphereHeight;
    float costTheta = dot(float3(0, 1, 0), dir);
    float2 uv = RemapTransmittanceUV(height, costTheta, params.PlanetRadius, radius1);
    return SAMPLE_TEXTURE2D(lut, samplerLUT, uv).rgb;
}

inline float3 ACESFilm(float3 x)
{
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}
#endif
