#include <metal_stdlib>
using namespace metal;

/**
 Vertex shader for rendering the liquid glass effect
 
 Generates a full-screen quad using vertex ID to create positions.
 This approach eliminates the need for vertex buffers.
 
 @param vertexID Index of the current vertex (0-3)
 @return Clip-space position for the vertex
 */
vertex float4 pixeluxLiquidGlassVertex(uint vertexID [[vertex_id]]) {
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    return float4(positions[vertexID], 0.0, 1.0);
}

/**
 Vertex shader for shared glass rendering surface
 
 Currently identical to pixeluxLiquidGlassVertex but maintained separately
 for potential future optimization of batch rendering.
 
 @param vertexID Index of the current vertex (0-3)
 @return Clip-space position for the vertex
 */
vertex float4 pixeluxLiquidGlassVertexShared(uint vertexID [[vertex_id]]) {
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    return float4(positions[vertexID], 0.0, 1.0);
}

/**
 Converts YCbCr color space to RGB
 
 Uses standard conversion matrix for video range YCbCr.
 
 @param y Luminance component
 @param cbcr Chrominance components
 @return RGB color values
 */
float3 pixeluxConvertYCbCrToRGB(float y, float2 cbcr) {
    float3 rgb;
    y = (y - 16.0/255.0) * 1.164;
    float cb = cbcr.x - 0.5;
    float cr = cbcr.y - 0.5;
    
    rgb.r = y + 1.596 * cr;
    rgb.g = y - 0.392 * cb - 0.813 * cr;
    rgb.b = y + 2.017 * cb;
    
    return saturate(rgb);
}

/**
 Signed distance function for rounded rectangle
 
 Calculates the distance from a point to the edge of a rounded rectangle.
 Negative values indicate points inside the shape.
 
 @param pos Position relative to rectangle center
 @param halfSize Half dimensions of the rectangle
 @param radius Corner radius
 @return Signed distance to the shape edge
 */
float pixeluxSdRoundedRect(float2 pos, float2 halfSize, float radius) {
    radius = min(radius, min(halfSize.x, halfSize.y));
    float2 q = abs(pos) - halfSize + radius;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

/**
 Smooth minimum function for blending signed distance fields
 
 Creates smooth transitions between shapes for fluid merging effects.
 
 @param a First distance value
 @param b Second distance value
 @param k Smoothing factor
 @return Smoothly blended minimum value
 */
float pixeluxSmin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

/**
 Fragment shader for non-interactive liquid glass effect
 
 Renders a single glass element with refraction, blur, and lighting effects.
 Processes AR camera frames with proper aspect ratio correction and
 coordinate transformations.
 
 @param position Screen-space position
 @param yTexture Y plane texture (luminance)
 @param cbcrTexture CbCr plane texture (chrominance)
 @param viewSize Viewport dimensions
 @param glassFrame Glass bounds (x, y, width, height)
 @param cornerRadius Corner radius for rounded rectangle
 @param blurIntensity Blur strength (0-1)
 @param displayTransform AR display transform matrix
 @param isYCbCr Whether input is YCbCr format
 @param screenSize Screen dimensions in pixels
 @param glassScreenPos Glass position in screen space
 @param cameraSize Camera image dimensions
 @param screenAspectRatio Screen aspect ratio
 @param isLandscape Device orientation flag
 @return Final color with alpha
 */
fragment float4 pixeluxLiquidGlassFragmentEnhanced(float4 position [[position]],
                                        texture2d<float> yTexture [[texture(0)]],
                                        texture2d<float> cbcrTexture [[texture(1)]],
                                        constant float2 &viewSize [[buffer(0)]],
                                        constant float4 &glassFrame [[buffer(1)]],
                                        constant float &cornerRadius [[buffer(2)]],
                                        constant float &blurIntensity [[buffer(3)]],
                                        constant float3x3 &displayTransform [[buffer(4)]],
                                        constant bool &isYCbCr [[buffer(5)]],
                                        constant float2 &screenSize [[buffer(6)]],
                                        constant float4 &glassScreenPos [[buffer(7)]],
                                        constant float2 &cameraSize [[buffer(8)]],
                                        constant float &screenAspectRatio [[buffer(9)]],
                                        constant bool &isLandscape [[buffer(10)]]) {
    
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    
    float2 glassLocalUV = position.xy / viewSize;
    
    float2 glassMin = glassFrame.xy / viewSize;
    float2 glassMax = (glassFrame.xy + glassFrame.zw) / viewSize;
    
    if (glassLocalUV.x < glassMin.x || glassLocalUV.x > glassMax.x ||
        glassLocalUV.y < glassMin.y || glassLocalUV.y > glassMax.y) {
        discard_fragment();
    }
    
    float2 glassCenter = (glassMin + glassMax) * 0.5;
    float2 glassSize = glassMax - glassMin;
    
    float2 relativePos = glassLocalUV - glassCenter;
    
    float2 glassSizePixels = glassSize * viewSize;
    float2 relativePosPixels = relativePos * viewSize;
    
    float2 halfSize = glassSizePixels * 0.5;
    
    float sdf = pixeluxSdRoundedRect(relativePosPixels, halfSize, cornerRadius);
    
    if (sdf > 0.0) {
        discard_fragment();
    }
    
    float normalizedSDF = saturate(-sdf / min(halfSize.x, halfSize.y));
    
    float sharp = 32.0;
    float rb1 = saturate(-sdf / sharp * 32.0);
    
    float borderWidth = 1.0;
    float rb2 = saturate(-(sdf + borderWidth) / sharp * 16.0) -
                saturate(-sdf / sharp * 16.0);
    
    float gradientWidth = 4.0;
    float rb3 = saturate(-(sdf + gradientWidth) / sharp * 4.0) -
                saturate(-(sdf - gradientWidth) / sharp * 4.0);
    
    float transition = smoothstep(0.0, 1.0, rb1);
    
    if (transition <= 0.0) {
        discard_fragment();
    }
    
    float2 normalizedGlassPos = (glassLocalUV - glassMin) / glassSize;
    
    float2 glassPixelPos = normalizedGlassPos * glassScreenPos.zw;
    
    float2 screenPixelPos = glassScreenPos.xy + glassPixelPos;
    float2 screenUV = screenPixelPos / screenSize;
    
    float cameraAspect = cameraSize.x / cameraSize.y;
    
    float2 centeredUV = screenUV - 0.5;
    
    if (screenAspectRatio > cameraAspect) {
        float scale = cameraAspect / screenAspectRatio;
        centeredUV.y *= scale;
    } else {
        float scale = screenAspectRatio / cameraAspect;
        centeredUV.x *= scale;
    }
    
    float containerScale = min(glassSizePixels.x, glassSizePixels.y) / 240.0;
    float lens_refraction = 0.15 * containerScale;
    
    float refractionStrength = saturate(-sdf / (lens_refraction * min(halfSize.x, halfSize.y)));
    
    float2 lensUV = centeredUV * sin(pow(refractionStrength, 0.25) * 1.57) + 0.5;
    
    float3 transformed = displayTransform * float3(lensUV, 1.0);
    float2 textureUV = transformed.xy;
    
    textureUV = 1.0 - textureUV;
    
    float4 glassColor = float4(0.0);
    
    float baseBlur = blurIntensity * 4.0;
    float edgeBlur = (1.0 - normalizedSDF) * 2.0;
    float totalBlur = baseBlur + edgeBlur;
    
    if (totalBlur < 0.5) {
        if (isYCbCr) {
            float y_val = yTexture.sample(textureSampler, textureUV).r;
            float2 cbcr = cbcrTexture.sample(textureSampler, textureUV).rg;
            glassColor.rgb = pixeluxConvertYCbCrToRGB(y_val, cbcr);
            glassColor.a = 1.0;
        } else {
            glassColor = yTexture.sample(textureSampler, textureUV);
        }
    } else {
        float total = 0.0;
        
        for (int x = -4; x <= 4; x++) {
            for (int y = -4; y <= 4; y++) {
                float2 offset = float2(x, y) * 0.5 / screenSize;
                float2 sampleUV = textureUV + offset * totalBlur;
                
                if (isYCbCr) {
                    float y_val = yTexture.sample(textureSampler, sampleUV).r;
                    float2 cbcr = cbcrTexture.sample(textureSampler, sampleUV).rg;
                    glassColor.rgb += pixeluxConvertYCbCrToRGB(y_val, cbcr);
                } else {
                    glassColor += yTexture.sample(textureSampler, sampleUV);
                }
                total += 1.0;
            }
        }
        glassColor /= total;
        glassColor.a = 1.0;
    }
    
    float2 m2 = relativePos / glassSize;
    
    float gradient = saturate((clamp(m2.y, 0.0, 0.2) + 0.1) / 2.0) +
                    saturate((clamp(-m2.y, -1.0, 0.2) * rb3 + 0.1) / 2.0);
    
    float4 lighting = glassColor + float4(rb2) + gradient * 1.0;
    lighting = saturate(lighting);
    
    lighting.rgb *= transition;
    
    return float4(lighting.rgb, transition);
}

/**
 Fragment shader for interactive liquid glass effect with merging
 
 Extends the enhanced shader with support for blending multiple glass
 instances. Calculates smooth transitions between nearby glass elements
 for fluid, water-like merging animations.
 
 @param position Screen-space position
 @param yTexture Y plane texture (luminance)
 @param cbcrTexture CbCr plane texture (chrominance)
 @param viewSize Viewport dimensions
 @param glassFrame Glass bounds (x, y, width, height)
 @param cornerRadius Corner radius for rounded rectangle
 @param blurIntensity Blur strength (0-1)
 @param displayTransform AR display transform matrix
 @param isYCbCr Whether input is YCbCr format
 @param screenSize Screen dimensions in pixels
 @param glassScreenPos Glass position in screen space
 @param cameraSize Camera image dimensions
 @param screenAspectRatio Screen aspect ratio
 @param isLandscape Device orientation flag
 @param interactiveCount Number of nearby interactive glasses
 @param interactiveGlasses Array of nearby glass data
 @return Final color with alpha
 */
fragment float4 pixeluxLiquidGlassFragmentInteractive(float4 position [[position]],
                                        texture2d<float> yTexture [[texture(0)]],
                                        texture2d<float> cbcrTexture [[texture(1)]],
                                        constant float2 &viewSize [[buffer(0)]],
                                        constant float4 &glassFrame [[buffer(1)]],
                                        constant float &cornerRadius [[buffer(2)]],
                                        constant float &blurIntensity [[buffer(3)]],
                                        constant float3x3 &displayTransform [[buffer(4)]],
                                        constant bool &isYCbCr [[buffer(5)]],
                                        constant float2 &screenSize [[buffer(6)]],
                                        constant float4 &glassScreenPos [[buffer(7)]],
                                        constant float2 &cameraSize [[buffer(8)]],
                                        constant float &screenAspectRatio [[buffer(9)]],
                                        constant bool &isLandscape [[buffer(10)]],
                                        constant int32_t &interactiveCount [[buffer(11)]],
                                        constant float4 *interactiveGlasses [[buffer(12)]]) {
    
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    
    float2 glassLocalUV = position.xy / viewSize;
    
    float2 glassMin = glassFrame.xy / viewSize;
    float2 glassMax = (glassFrame.xy + glassFrame.zw) / viewSize;
    
    float2 glassCenter = (glassMin + glassMax) * 0.5;
    float2 glassSize = glassMax - glassMin;
    
    float2 relativePos = glassLocalUV - glassCenter;
    
    float2 glassSizePixels = glassSize * viewSize;
    float2 relativePosPixels = relativePos * viewSize;
    
    float2 halfSize = glassSizePixels * 0.5;
    
    float sdf = pixeluxSdRoundedRect(relativePosPixels, halfSize, cornerRadius);
    float originalSdf = sdf;
    
    float blendRadius = min(halfSize.x, halfSize.y) * 0.8;
    
    bool inBlendZone = false;
    float blendStrength = 0.0;
    
    for (int i = 0; i < interactiveCount; i++) {
        float4 otherGlass = interactiveGlasses[i];
        float2 otherPos = otherGlass.xy;
        float otherRadius = otherGlass.z;
        float otherCornerRadius = otherGlass.w;
        
        float2 otherPosPixels = otherPos;
        
        float2 toOther = relativePosPixels - otherPosPixels;
        float distToOther = length(toOther);
        
        float otherSdf;
        if (otherCornerRadius > 0.1) {
            float2 otherHalfSize = float2(otherRadius);
            otherSdf = pixeluxSdRoundedRect(toOther, otherHalfSize, otherCornerRadius);
        } else {
            otherSdf = distToOther - otherRadius;
        }
        
        float blendDist = max(0.0, blendRadius - abs(sdf - otherSdf));
        if (blendDist > 0.0) {
            inBlendZone = true;
            float localBlend = smoothstep(0.0, blendRadius, blendDist);
            blendStrength = max(blendStrength, localBlend);
            
            float k = blendRadius * 0.5;
            sdf = pixeluxSmin(sdf, otherSdf, k);
        }
    }
    
    if (sdf > 0.0 && originalSdf > 0.0) {
        discard_fragment();
    }
    
    float normalizedSDF = saturate(-sdf / min(halfSize.x, halfSize.y));
    
    float sharp = 32.0;
    float rb1 = saturate(-sdf / sharp * 32.0);
    float borderWidth = 1.0;
    float rb2 = saturate(-(sdf + borderWidth) / sharp * 16.0) -
                saturate(-sdf / sharp * 16.0);
    float gradientWidth = 4.0;
    float rb3 = saturate(-(sdf + gradientWidth) / sharp * 4.0) -
                saturate(-(sdf - gradientWidth) / sharp * 4.0);
    
    float transition = smoothstep(0.0, 1.0, rb1);
    
    if (transition <= 0.0) {
        discard_fragment();
    }
    
    float2 normalizedGlassPos = (glassLocalUV - glassMin) / glassSize;
    
    float2 glassPixelPos = normalizedGlassPos * glassScreenPos.zw;
    
    float2 screenPixelPos = glassScreenPos.xy + glassPixelPos;
    float2 screenUV = screenPixelPos / screenSize;
    
    float cameraAspect = cameraSize.x / cameraSize.y;
    
    float2 centeredUV = screenUV - 0.5;
    
    if (screenAspectRatio > cameraAspect) {
        float scale = cameraAspect / screenAspectRatio;
        centeredUV.y *= scale;
    } else {
        float scale = screenAspectRatio / cameraAspect;
        centeredUV.x *= scale;
    }
    
    float containerScale = min(glassSizePixels.x, glassSizePixels.y) / 240.0;
    float lens_refraction = 0.15 * containerScale;
    
    float refractionStrength = saturate(-sdf / (lens_refraction * min(halfSize.x, halfSize.y)));
    
    float exponentialDistortion = exp(refractionStrength * 2.0) - 1.0;
    refractionStrength = mix(refractionStrength, exponentialDistortion, 0.3);
    
    float2 lensUV = centeredUV * sin(pow(refractionStrength, 0.25) * 1.57) + 0.5;
    
    float3 transformed = displayTransform * float3(lensUV, 1.0);
    float2 textureUV = transformed.xy;
    
    textureUV = 1.0 - textureUV;
    
    float4 glassColor = float4(0.0);
    
    float baseBlur = blurIntensity * 1.5;
    float edgeBlur = (1.0 - normalizedSDF) * 0.3;
    
    float blendBlur = 0.0;
    if (inBlendZone) {
        blendBlur = blendStrength * 0.2;
    }
    
    float totalBlur = baseBlur + edgeBlur + blendBlur;
    
    if (totalBlur < 0.5) {
        if (isYCbCr) {
            float y_val = yTexture.sample(textureSampler, textureUV).r;
            float2 cbcr = cbcrTexture.sample(textureSampler, textureUV).rg;
            glassColor.rgb = pixeluxConvertYCbCrToRGB(y_val, cbcr);
            glassColor.a = 1.0;
        } else {
            glassColor = yTexture.sample(textureSampler, textureUV);
        }
    } else {
        float total = 0.0;
        
        for (int x = -4; x <= 4; x++) {
            for (int y = -4; y <= 4; y++) {
                float2 offset = float2(x, y) * 0.5 / screenSize;
                float2 sampleUV = textureUV + offset * totalBlur;
                
                if (isYCbCr) {
                    float y_val = yTexture.sample(textureSampler, sampleUV).r;
                    float2 cbcr = cbcrTexture.sample(textureSampler, sampleUV).rg;
                    glassColor.rgb += pixeluxConvertYCbCrToRGB(y_val, cbcr);
                } else {
                    glassColor += yTexture.sample(textureSampler, sampleUV);
                }
                total += 1.0;
            }
        }
        glassColor /= total;
        glassColor.a = 1.0;
    }
    
    float2 m2 = relativePos / glassSize;
    
    float gradient = saturate((clamp(m2.y, 0.0, 0.2) + 0.1) / 3.0) +
                    saturate((clamp(-m2.y, -1.0, 0.2) * rb3 + 0.1) / 3.0);
    
    if (interactiveCount > 0 && blendBlur > 0.1) {
        gradient += blendBlur * 0.15;
    }
    
    float4 lighting = glassColor + float4(rb2 * 0.5) + gradient * 0.5;
    lighting = saturate(lighting);
    
    lighting.rgb *= transition;
    
    float edgeThickness = 0.008;
    float edgeMask = smoothstep(edgeThickness, 0.0, abs(sdf));
    
    if (edgeMask > 0.0) {
        float2 normalizedPos = (relativePosPixels / min(halfSize.x, halfSize.y)) * 1.5;
        
        float diagonal1 = abs(normalizedPos.x + normalizedPos.y);
        float diagonal2 = abs(normalizedPos.x - normalizedPos.y);
        
        float diagonalFactor = max(
            smoothstep(1.0, 0.1, diagonal1),
            smoothstep(1.0, 0.5, diagonal2)
        );
        
        if (blendBlur > 0.1) {
            diagonalFactor = mix(diagonalFactor, 1.0, blendBlur * 0.5);
        }
        
        diagonalFactor = pow(diagonalFactor, 1.8);
        
        float3 edgeWhite = float3(1.2);
        float3 internalColor = lighting.rgb * 0.4;
        
        float3 edgeColor = mix(internalColor, edgeWhite, diagonalFactor);
        lighting.rgb = mix(lighting.rgb, edgeColor, edgeMask);
    }
    
    return float4(lighting.rgb, transition);
}

/**
 Fragment shader for batch rendering multiple glasses in a single pass
 
 Optimized shader for rendering all interactive glasses together.
 This approach reduces draw calls and improves performance when
 multiple glass elements are visible.
 
 @param position Screen-space position
 @param yTexture Y plane texture (luminance)
 @param cbcrTexture CbCr plane texture (chrominance)
 @param viewSize Viewport dimensions
 @param displayTransform AR display transform matrix
 @param isYCbCr Whether input is YCbCr format
 @param screenSize Screen dimensions in pixels
 @param cameraSize Camera image dimensions
 @param screenAspectRatio Screen aspect ratio
 @param glassCount Number of glasses to render
 @param glassData Array of glass bounds
 @param glassProperties Array of glass properties
 @return Final color with alpha
 */
fragment float4 pixeluxLiquidGlassFragmentShared(float4 position [[position]],
                                         texture2d<float> yTexture [[texture(0)]],
                                         texture2d<float> cbcrTexture [[texture(1)]],
                                         constant float2 &viewSize [[buffer(0)]],
                                         constant float3x3 &displayTransform [[buffer(1)]],
                                         constant bool &isYCbCr [[buffer(2)]],
                                         constant float2 &screenSize [[buffer(3)]],
                                         constant float2 &cameraSize [[buffer(4)]],
                                         constant float &screenAspectRatio [[buffer(5)]],
                                         constant int32_t &glassCount [[buffer(6)]],
                                         constant float4 *glassData [[buffer(7)]],
                                         constant float4 *glassProperties [[buffer(8)]]) {
    
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    
    float2 pixelPos = position.xy;
    
    float combinedSDF = 10000.0;
    int closestGlassIndex = -1;
    float closestDistance = 10000.0;
    
    for (int i = 0; i < glassCount; i++) {
        float4 glass = glassData[i];
        float2 glassCenter = glass.xy + glass.zw * 0.5;
        float2 glassHalfSize = glass.zw * 0.5;
        
        float2 relPos = pixelPos - glassCenter;
        
        float cornerRadius = glassProperties[i].x;
        float sdf = pixeluxSdRoundedRect(relPos, glassHalfSize, cornerRadius);
        
        if (sdf < closestDistance) {
            closestDistance = sdf;
            closestGlassIndex = i;
        }
    }
    
    if (closestGlassIndex == -1 || closestDistance > 100.0) {
        discard_fragment();
    }
    
    float4 primaryGlass = glassData[closestGlassIndex];
    float2 primaryCenter = primaryGlass.xy + primaryGlass.zw * 0.5;
    float2 primaryHalfSize = primaryGlass.zw * 0.5;
    float primaryRadius = glassProperties[closestGlassIndex].x;
    
    combinedSDF = closestDistance;
    
    float blendRadius = min(primaryHalfSize.x, primaryHalfSize.y) * 0.8;
    
    for (int i = 0; i < glassCount; i++) {
        if (i == closestGlassIndex) continue;
        
        float4 otherGlass = glassData[i];
        float2 otherCenter = otherGlass.xy + otherGlass.zw * 0.5;
        float2 otherHalfSize = otherGlass.zw * 0.5;
        float otherRadius = glassProperties[i].x;
        
        float centerDist = length(primaryCenter - otherCenter);
        float touchDist = length(primaryHalfSize) + length(otherHalfSize);
        
        if (centerDist < touchDist + blendRadius * 2.0) {
            float2 relPosOther = pixelPos - otherCenter;
            float otherSdf = pixeluxSdRoundedRect(relPosOther, otherHalfSize, otherRadius);
            
            float k = blendRadius * 0.5;
            combinedSDF = pixeluxSmin(combinedSDF, otherSdf, k);
        }
    }
    
    if (combinedSDF > 0.0) {
        discard_fragment();
    }
    
    float blurIntensity = glassProperties[closestGlassIndex].y;
    
    float normalizedSDF = saturate(-combinedSDF / min(primaryHalfSize.x, primaryHalfSize.y));
    
    float sharp = 32.0;
    float rb1 = saturate(-combinedSDF / sharp * 32.0);
    float borderWidth = 1.0;
    float rb2 = saturate(-(combinedSDF + borderWidth) / sharp * 16.0) -
                saturate(-combinedSDF / sharp * 16.0);
    float gradientWidth = 4.0;
    float rb3 = saturate(-(combinedSDF + gradientWidth) / sharp * 4.0) -
                saturate(-(combinedSDF - gradientWidth) / sharp * 4.0);
    
    float transition = smoothstep(0.0, 1.0, rb1);
    
    if (transition <= 0.0) {
        discard_fragment();
    }
    
    float2 screenUV = pixelPos / screenSize;
    
    float cameraAspect = cameraSize.x / cameraSize.y;
    float2 centeredUV = screenUV - 0.5;
    
    if (screenAspectRatio > cameraAspect) {
        float scale = cameraAspect / screenAspectRatio;
        centeredUV.y *= scale;
    } else {
        float scale = screenAspectRatio / cameraAspect;
        centeredUV.x *= scale;
    }
    
    float containerScale = min(primaryHalfSize.x, primaryHalfSize.y) / 240.0;
    float lens_refraction = 0.15 * containerScale;
    float refractionStrength = saturate(-closestDistance / (lens_refraction * min(primaryHalfSize.x, primaryHalfSize.y)));
    
    float exponentialDistortion = exp(refractionStrength * 2.0) - 1.0;
    refractionStrength = mix(refractionStrength, exponentialDistortion, 0.3);
    
    float2 lensUV = centeredUV * sin(pow(refractionStrength, 0.25) * 1.57) + 0.5;
    
    float3 transformed = displayTransform * float3(lensUV, 1.0);
    float2 textureUV = 1.0 - transformed.xy;
    
    float4 glassColor = float4(0.0);
    
    float baseBlur = blurIntensity * 1.5;
    float edgeBlur = (1.0 - normalizedSDF) * 0.3;
    float totalBlur = baseBlur + edgeBlur;
    
    if (totalBlur < 0.5) {
        if (isYCbCr) {
            float y_val = yTexture.sample(textureSampler, textureUV).r;
            float2 cbcr = cbcrTexture.sample(textureSampler, textureUV).rg;
            glassColor.rgb = pixeluxConvertYCbCrToRGB(y_val, cbcr);
            glassColor.a = 1.0;
        } else {
            glassColor = yTexture.sample(textureSampler, textureUV);
        }
    } else {
        float total = 0.0;
        for (int x = -4; x <= 4; x++) {
            for (int y = -4; y <= 4; y++) {
                float2 offset = float2(x, y) * 0.5 / screenSize;
                float2 sampleUV = textureUV + offset * totalBlur;
                
                if (isYCbCr) {
                    float y_val = yTexture.sample(textureSampler, sampleUV).r;
                    float2 cbcr = cbcrTexture.sample(textureSampler, sampleUV).rg;
                    glassColor.rgb += pixeluxConvertYCbCrToRGB(y_val, cbcr);
                } else {
                    glassColor += yTexture.sample(textureSampler, sampleUV);
                }
                total += 1.0;
            }
        }
        glassColor /= total;
        glassColor.a = 1.0;
    }
    
    float2 relativePos = pixelPos - primaryCenter;
    float2 m2 = relativePos / primaryGlass.zw;
    
    float gradient = saturate((clamp(m2.y, 0.0, 0.2) + 0.1) / 3.0) +
                    saturate((clamp(-m2.y, -1.0, 0.2) * rb3 + 0.1) / 3.0);
    
    float4 lighting = glassColor + float4(rb2 * 0.5) + gradient * 0.5;
    lighting = saturate(lighting);
    lighting.rgb *= transition;
    
    float edgeThickness = 0.008;
    float edgeMask = smoothstep(edgeThickness, 0.0, abs(combinedSDF));
    
    if (edgeMask > 0.0) {
        float2 normalizedPos = (relativePos / min(primaryHalfSize.x, primaryHalfSize.y)) * 1.5;
        
        float diagonal1 = abs(normalizedPos.x + normalizedPos.y);
        float diagonal2 = abs(normalizedPos.x - normalizedPos.y);
        
        float diagonalFactor = max(
            smoothstep(1.0, 0.1, diagonal1),
            smoothstep(1.0, 0.5, diagonal2)
        );
        
        diagonalFactor = pow(diagonalFactor, 1.8);
        
        float3 edgeWhite = float3(1.2);
        float3 internalColor = lighting.rgb * 0.4;
        
        float3 edgeColor = mix(internalColor, edgeWhite, diagonalFactor);
        lighting.rgb = mix(lighting.rgb, edgeColor, edgeMask);
    }
    
    return float4(lighting.rgb, transition);
}