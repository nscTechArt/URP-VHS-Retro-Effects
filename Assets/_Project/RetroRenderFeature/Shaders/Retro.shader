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
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
        
        CBUFFER_START(UnityPerMaterial)
        float4 _MainTex_ST;
        float4 _MainTex_TexelSize; 
        CBUFFER_END

        TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
        
        struct Attributes
        {
            float4 pos: POSITION;
	        float2 uv: TEXCOORD0;
        };

        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float2 uv: TEXCOORD0;
        };

        Varyings Vertex(Attributes input)
        {
            Varyings output;
            output.positionCS = TransformObjectToHClip(input.pos.xyz);
            output.uv = input.uv;
            return output;
        }
        
        ENDHLSL
        
        Pass // Blur DownSample
        {
            Name "Blur DownSample Pass"
            
            HLSLPROGRAM
            #pragma vertex BlurVertex
            #pragma fragment BlurFragment

            float _BlurBias;
            
            struct CustomVaryings
            {
                float4 positionCS : SV_POSITION;
                float2 uvs[4]     : TEXCOORD0; 
            };

            CustomVaryings BlurVertex(Attributes input)
            {
                CustomVaryings output;
                output.positionCS = TransformObjectToHClip(input.pos.xyz);
                
                float left = -1 - _BlurBias;
                float right = 1 - _BlurBias;
                float2 blurOffset = _MainTex_TexelSize.xy * float2(1, 0.5);
                output.uvs[0] = input.uv + float2(blurOffset.x * left,  -blurOffset.y);
                output.uvs[1] = input.uv + float2(blurOffset.x * right, -blurOffset.y);
                output.uvs[2] = input.uv + float2(blurOffset.x * left,   blurOffset.y);
                output.uvs[3] = input.uv + float2(blurOffset.x * right,  blurOffset.y);
                
                return output;
            }

            half4 BlurFragment(CustomVaryings input) : SV_Target
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

        Pass // Blur UpSample
        {
            Name "Blur UpSample Pass"
            
            Blend SrcAlpha OneMinusSrcAlpha
            
            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment BlurUpSampleFragment

            float _UpsampleFactor;
            
            half4 BlurUpSampleFragment(Varyings input) : SV_Target
            {
                half4 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
                color.a = _UpsampleFactor;
                return color;
            }
            
            ENDHLSL
        }

        Pass // Smear 0
        {
            Name "Smear Pass 0"
            
            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment SmearFragment
            
            float _SmearTextureTexelSize;
            #define _Falloff 0.3
            #define _Offset 1.0
            
            half4 SmearFragment(Varyings input) : SV_Target
            {
                half4 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
                float energy = 1;
                const uint SMEAR_LENGTH = 4;
                [unroll]
                for (uint i = 1; i <= SMEAR_LENGTH; i++)
                {
                    float falloff = exp(-_Falloff * i);
                    energy += falloff;
                    float u = input.uv.x - _SmearTextureTexelSize * _Offset * i;
                    color += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, float2(u, input.uv.y)) * falloff;
                }
                return color / energy;
            }
            
            ENDHLSL
        }

        Pass // Smear 1
        {
            Name "Smear Pass 1"
            
            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment SmearFragment
            
            float _SmearTextureTexelSize;
            #define _Falloff 1.2
            #define _Offset 5.0
            
            half4 SmearFragment(Varyings input) : SV_Target
            {
                half4 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
                float energy = 1;
                const uint SMEAR_LENGTH = 4;
                [unroll]
                for (uint i = 1; i <= SMEAR_LENGTH; i++)
                {
                    float falloff = exp(-_Falloff * i);
                    energy += falloff;
                    float u = input.uv.x - _SmearTextureTexelSize * _Offset * i;
                    color += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, float2(u, input.uv.y)) * falloff;
                }
                return color / energy;
            }
            
            ENDHLSL
        }

        Pass // Composite
        {
            Name "Composite Pass"
            
            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment CompositeFragment

            TEXTURE2D(_SlightBlurredTexture); SAMPLER(sampler_SlightBlurredTexture);
            TEXTURE2D(_BlurredTexture); SAMPLER(sampler_BlurredTexture);
            TEXTURE2D(_SmearTexture); SAMPLER(sampler_SmearTexture);
            float _BleedIntensity;
            float _SmearIntensity;
            float _EdgeIntensity;
            float _EdgeDistance;
            float _TapeNoiseAmount;
            float _TapeNoiseSpeed;
            float _TapeNoiseAlpha;
            float _InterlacingAmount;
            float _BleedAmount;
            float _ScanlineSpeed;
            float _ScanlineFrequency;
            float _ScanlineIntensity;
            

            half3 RGBToYCbCr(half3 rgb)
            {
                return half3(0.0625 + 0.257 * rgb.r + 0.50412 * rgb.g + 0.0979 * rgb.b,
                    0.5 - 0.14822 * rgb.r - 0.290 * rgb.g + 0.43921 * rgb.b,
                    0.5 + 0.43921 * rgb.r - 0.3678 * rgb.g - 0.07142 * rgb.b);
            }
            
            half3 YCbCrToRGB(half3 ycbcr)
            {
                ycbcr -= half3(0.0625, 0.5, 0.5);
                return half3(1.164 * ycbcr.x + 1.596 * ycbcr.z,
                    1.164 * ycbcr.x - 0.392 * ycbcr.y - 0.813 * ycbcr.z,
                    1.164 * ycbcr.x + 2.017 * ycbcr.y);
            }

            float Rand (in float2 st)
            {
                return frac(sin(dot(st.xy, float2(12.9898,78.233)))*43758.5453123);
            }

            half Hash(half n)
            {
                return frac( sin(n) * 43758.5453123);
            }

            half Hash12(half2 p)
            {
                half3 p3  = frac(p.xyx * half3(443.8975,397.2973, 491.1871));
                p3 += dot(p3, p3.yzx + 19.19);
                return frac(p3.x * p3.z * p3.y);
            }
            
            half NoiseFromIQ(half3 x)
            {
               half3 p = floor(x);
               half3 f = frac(x);
               f = f * f * (3.0 - 2.0 * f);
               half n = p.x + p.y * 57.0 + 113.0 * p.z;
               return lerp(lerp(lerp(Hash(n +   0.), Hash(n +   1.), f.x),
                                lerp(Hash(n +  57.), Hash(n +  57.), f.x), f.y),
                           lerp(lerp(Hash(n + 113.), Hash(n + 114.), f.x),
                                lerp(Hash(n + 170.), Hash(n + 171.), f.x), f.y), f.z);
            }
            
            half TapeNoise(half2 uv)
            {
                half t = _Time.y * _TapeNoiseSpeed;
                
                // generate line noises
                // --------------------
                uv.y = 1 - uv.y;
                half y = uv.y * _ScreenParams.y;
                half lineNoise = NoiseFromIQ( half3(y * 0.012 +   0 + t, 1, 1) ) *
                                 NoiseFromIQ( half3(y * 0.091 + 200 + t, 1, 1) ) *
                                 NoiseFromIQ( half3(y * 0.917 + 421 + t, 1, 1) );

                // generate noise mask
                // -------------------
                half noiseMask =  Hash12(frac(uv + t * half2(0.234, 0.637)));
                noiseMask = noiseMask * noiseMask * noiseMask + 0.3;

                // generate tape noise
                // -------------------
                half tapeNoise = lineNoise * noiseMask;

                // saturate tape noise
                // -------------------
                tapeNoise = step(1 - _TapeNoiseAmount, tapeNoise);
                
                return tapeNoise * _TapeNoiseAlpha;
            }

            half InterlacingOffset(half2 uv)
            {
                half offset = uv.y + _Time.y;
                offset *= _ScreenParams.y;
                offset = floor(offset);
                offset = fmod(offset, 2.75);
                offset *= _InterlacingAmount;
                offset *= rcp(_ScreenParams.x);
                return offset;
            }

            half Scanlines(half2 uv)
            {
                half scroll = _Time.y * _ScanlineSpeed;
                return sin((uv.y + scroll) * _ScanlineFrequency * 2.0 * 3.1416);
            }

            half4 CompositeFragment(Varyings input) : SV_Target
            {
                // vertical wrapping
                // -----------------
                float2 uv = input.uv;
                uv.y = frac(uv.y + lerp(0.0, 0.3, frac(_Time.z * 3.0) * step(0.97, Rand(floor(_Time.z * 3.0)))));

                // interlacing
                // -----------
                uv.x += InterlacingOffset(uv);
                
                // scene color
                // -----------
                half3 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv).rgb;
                
                // edge sharpening
                // ---------------
                float2 slightBlurredUV = uv - float2(_EdgeDistance, 0);
                half3 slightBlurredColor = SAMPLE_TEXTURE2D(_SlightBlurredTexture, sampler_SlightBlurredTexture, slightBlurredUV).rgb;
                half3 edge = color - slightBlurredColor;
                color += edge * _EdgeIntensity;
                
                // smearing
                // --------
                half3 smearColor = SAMPLE_TEXTURE2D(_SmearTexture, sampler_SmearTexture, uv).rgb;
                color = lerp(color, smearColor, _SmearIntensity);
                
                // color bleeding
                // --------------
                color = RGBToYCbCr(color);
                half3 blurredColor = SAMPLE_TEXTURE2D(_BlurredTexture, sampler_BlurredTexture, uv).rgb;
                blurredColor = RGBToYCbCr(blurredColor);
                color.gb = lerp(color.gb, blurredColor.gb, _BleedIntensity);
                color = YCbCrToRGB(color);

                // tape noises
                // -----------
                color += TapeNoise(uv);

                // scanlines
                // ---------
                color = lerp(color, color * Scanlines(uv), _ScanlineIntensity);
     
                return half4(color, 1);
            }
            
            ENDHLSL
        }
    }
}
