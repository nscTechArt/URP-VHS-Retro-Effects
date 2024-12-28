Shader "Hidden/RetroBlur"
{
    Properties
    {
        _MainTex("Texture", 2D) = "white" { }
    }
    
    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "RenderPipeline"="UniversalPipeline"
        }
        ZWrite Off ZTest Always Cull Off
        
        HLSLINCLUDE

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        struct Attributes
        {
            float4 pos: POSITION;
	        float2 uv: TEXCOORD0;
        };
        
        TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
        
        CBUFFER_START(UnityPerMaterial)
        float4 _MainTex_ST;
        float4 _MainTex_TexelSize; 
        CBUFFER_END
        
        ENDHLSL
        
        Pass // Blur Downsample
        {
            Name "Blur Downsample Pass"
            
            HLSLPROGRAM
            #pragma vertex BlurDownSampleVertex
            #pragma fragment BlurDownSampleFragment
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uvs[4]     : TEXCOORD0; 
            };

            Varyings BlurDownSampleVertex(Attributes input)
            {
                Varyings output;

                // position
                // --------
                output.positionCS = TransformObjectToHClip(input.pos.xyz);

                // uvs with offsets
                // ----------------
                float2 uv = input.uv;
                float2 texelSize = _MainTex_TexelSize.xy;
                output.uvs[0] = uv + texelSize * 0.5;
                output.uvs[1] = uv + float2(0, texelSize.y) - texelSize * 0.5;
                output.uvs[2] = uv + float2(texelSize.x, 0) - texelSize * 0.5;
                output.uvs[3] = uv - texelSize * 0.5;
                
                return output;
            }

            half4 BlurDownSampleFragment(Varyings input) : SV_Target
            {
                half4 color = 0;
                color += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uvs[0]) * 0.25;
                color += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uvs[1]) * 0.25;
                color += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uvs[2]) * 0.25;
                color += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uvs[3]) * 0.25;
                return color;
            }
            
            ENDHLSL
        }

        Pass // Blur
        {
            Name "Blur Pass"
            
            HLSLPROGRAM
            #pragma vertex BlurVertex
            #pragma fragment BlurFragment

            float _BlurBias;
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uvs[4]     : TEXCOORD0; 
            };

            Varyings BlurVertex(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.pos.xyz);
                
                float left = -1 - _BlurBias;
                float right = 1 - _BlurBias;
                float2 blur = _MainTex_TexelSize.xy * float2(1, 0.5);
                float2 uv = input.uv;
                output.uvs[0] = uv + float2(blur.x * left,  -blur.y);
                output.uvs[1] = uv + float2(blur.x * right, -blur.y);
                output.uvs[2] = uv + float2(blur.x * left,   blur.y);
                output.uvs[3] = uv + float2(blur.x * right,  blur.y);
                
                return output;
            }

            half4 BlurFragment(Varyings input) : SV_Target
            {
                half4 color = 0;
                color += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uvs[0]) * 0.25;
                color += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uvs[1]) * 0.25;
                color += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uvs[2]) * 0.25;
                color += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uvs[3]) * 0.25;
                return color;
            }
            
            ENDHLSL
        }

        Pass // Blur Upsample
        {
            Name "Blur Upsample Pass"
            
            Blend SrcAlpha OneMinusSrcAlpha
            
            HLSLPROGRAM
            #pragma vertex BlurVertex
            #pragma fragment BlurUpsampleFragment

            float _UpsampleFactor;
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv: TEXCOORD0;
            };

            Varyings BlurVertex(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.pos.xyz);
                output.uv = input.uv;
                return output;
            }

            half4 BlurUpsampleFragment(Varyings input) : SV_Target
            {
                half4 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
                color.a = _UpsampleFactor;
                return color;
            }
            
            ENDHLSL
        }

        Pass // Smearing
        {
            Name "Smearing Pass"
            
            HLSLPROGRAM
            #pragma vertex SmearVertex
            #pragma fragment SmearFragment
            
            float4 _SmearTextureSize;
            float4 _SmearOffsetAttenuation;
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv: TEXCOORD0;
            };

            Varyings SmearVertex(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.pos.xyz);
                output.uv = input.uv;
                return output;
            }

            half4 SmearFragment(Varyings input) : SV_Target
            {
                half4 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
                float energy = 1;
                const uint SMEAR_LENGTH = 4;
                [unroll]
                for (uint i = 1; i <= SMEAR_LENGTH; i++)
                {
                    float falloff = exp(-_SmearOffsetAttenuation.y * i);
                    energy += falloff;
                    float u = input.uv.x - _SmearOffsetAttenuation.x * _SmearTextureSize.x * i;
                    color += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, float2(u, input.uv.y)) * falloff * (u > 0);
                }
                return color / energy;
            }
            
            ENDHLSL
        }

        Pass // Composite
        {
            Name "Composite Pass"
            
            HLSLPROGRAM
            #pragma vertex CompositeVertex
            #pragma fragment CompositeFragment

            TEXTURE2D(_SlightBlurredTexture); SAMPLER(sampler_SlightBlurredTexture);
            TEXTURE2D(_BlurredTexture); SAMPLER(sampler_BlurredTexture);
            TEXTURE2D(_SmearTexture); SAMPLER(sampler_SmearTexture);
            float _BleedIntensity;
            float _SmearIntensity;
            float _EdgeIntensity;
            float _EdgeDistance;
            
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv: TEXCOORD0;
            };

            Varyings CompositeVertex(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.pos.xyz);
                output.uv = input.uv;
                return output;
            }

            half3 RGBToYCbCr(half3 rgb)
            {
                return half3(0.0625 + 0.257 * rgb.r + 0.50412 * rgb.g + 0.0979 * rgb.b,
                    0.5 - 0.14822 * rgb.r - 0.290 * rgb.g + 0.43921 * rgb.b,
                    0.5 + 0.43921 * rgb.r - 0.3678 * rgb.g - 0.07142 * rgb.b);
            }
            
            half3 YCbCrToRGB(float3 ycbcr)
            {
                ycbcr -= half3(0.0625, 0.5, 0.5);
                return half3(1.164 * ycbcr.x + 1.596 * ycbcr.z,
                    1.164 * ycbcr.x - 0.392 * ycbcr.y - 0.813 * ycbcr.z,
                    1.164 * ycbcr.x + 2.017 * ycbcr.y);
            }

            half4 CompositeFragment(Varyings input) : SV_Target
            {
                float2 quarterTexelSize = _MainTex_TexelSize.xy * 0.25;
                half3 sharpColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv + quarterTexelSize).rgb;

                float2 slightBlurredUV = input.uv - float2(_EdgeDistance, 0);
                half3 slightBlurredColor = SAMPLE_TEXTURE2D(_SlightBlurredTexture, sampler_SlightBlurredTexture, slightBlurredUV).rgb;

                half3 edge = sharpColor - slightBlurredColor;
                sharpColor += edge * _EdgeIntensity;

                half3 smearColor = SAMPLE_TEXTURE2D(_SmearTexture, sampler_SmearTexture, input.uv).rgb;
                sharpColor = lerp(sharpColor, smearColor, _SmearIntensity);

                sharpColor = RGBToYCbCr(sharpColor.rgb);

                half3 blurredColor = SAMPLE_TEXTURE2D(_BlurredTexture, sampler_BlurredTexture, input.uv).rgb;
                blurredColor = RGBToYCbCr(blurredColor);

                sharpColor.gb = lerp(sharpColor.gb, blurredColor.gb, _BleedIntensity);
                sharpColor = YCbCrToRGB(sharpColor);
                
                return half4(sharpColor, 1);
            }
            
            ENDHLSL
        }
    }
}
