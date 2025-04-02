#ifndef CUSTOM_MATH
#define CUSTOM_MATH
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Macros.hlsl"
/// 计算球内一点到
/// @param height 球心距离
/// @param cosTheta 天顶角余弦
/// @param radius 球体半径
/// @return 
inline float DistanceToSphereByCos(float height, float cosTheta, float radius)
{
    float h = height;
    float h2 = h * h;
    float hCos = h * cosTheta;
    float dist = sqrt(hCos * hCos - h2 + radius * radius) - hCos;
    return dist;
}
/// 计算球内一点到
/// @param height 球心距离
/// @param dir 方向
/// @param radius 球体半径
/// @return 
inline float DistanceToSphere(float height, float3 dir, float radius)
{
    return DistanceToSphereByCos(height, dot(dir, float3(0, 1, 0)), radius);
}

/// 大小球心重合，求一高度向一方向打射线，射线与大小球较近交点的距离
/// @param height 距球心高度
/// @param dir 方向
/// @param radius0 小球体半径 
/// @param radius1 大球体半径
/// @return 
inline float DistanceToDualSphere(float height, float3 dir, float radius0, float radius1)
{
    float cosTheta = dot(dir, float3(0, 1, 0));
    float h2 = height * height;
    float r0_2 = radius0 * radius0;
    float cosTmp = -sqrt(h2 - r0_2)/height ;
    if (cosTheta >= cosTmp)
    {
        float dist1 = DistanceToSphereByCos(height, cosTheta, radius1);
        return dist1;
    }
    else
    {
        float cosThetaR0 = -cosTheta;
        float l0 = height * cosThetaR0;
        return height * cosThetaR0 - sqrt(r0_2 - h2 + l0 * l0);
    }
}
inline float DistToCos(float dist, float height, float radius)
{
    float cos = (-height*height + radius*radius - dist*dist) / (2*dist*height);
    return cos;
}
#endif
