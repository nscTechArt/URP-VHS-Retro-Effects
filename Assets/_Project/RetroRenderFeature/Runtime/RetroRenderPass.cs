using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class RetroRenderPass : ScriptableRenderPass
{
    public RetroRenderPass(string featureName, RetroSettings settings)
    {
        // initialize
        // ----------
        renderPassEvent = settings.m_RenderPassEvent;
        mProfilingSampler = new ProfilingSampler(featureName);
        mPassMaterial = CoreUtils.CreateEngineMaterial(settings.m_RetroShader);
    }

    public void Setup(Retro volumeComponent)
    {
        mVolumeComponent = volumeComponent;
        mPassMaterial.SetFloat(_BlurBias, mVolumeComponent.m_BleedDirection.value);
        mPassMaterial.SetFloat(_BleedIntensity, mVolumeComponent.m_BleedIntensity.value);
        mPassMaterial.SetFloat(_SmearIntensity, mVolumeComponent.m_SmearIntensity.value);
        mPassMaterial.SetFloat(_EdgeIntensity, mVolumeComponent.m_EdgeIntensity.value);
        mPassMaterial.SetFloat(_EdgeDistance, mVolumeComponent.m_EdgeDistance.value);
    }

    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        // setup pass source and destination
        // ---------------------------------
        mSourceRT = renderingData.cameraData.renderer.cameraColorTargetHandle;
        
        // setup temporary color texture
        // -----------------------------
        mDescriptor = renderingData.cameraData.cameraTargetDescriptor;
        mDescriptor.depthBufferBits = 0;
        mDescriptor.msaaSamples = 1;
        mDescriptor.colorFormat = RenderTextureFormat.Default;
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        CommandBuffer cmd = CommandBufferPool.Get();
        using (new ProfilingScope(cmd, mProfilingSampler))
        {
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            
            // retrieve screen size
            // --------------------
            int screenWidth = renderingData.cameraData.camera.pixelWidth;
            int screenHeight = renderingData.cameraData.camera.pixelHeight;
            
            // create blur pyramid
            // -------------------
            float blurAmount = Mathf.Clamp(Mathf.Log(screenWidth * mVolumeComponent.m_BleedRadius.value * 0.25f, 2f), 3, 8);
            int blurIterations = Mathf.FloorToInt(blurAmount);
            if (mBlurPyramid == null || mBlurPyramid.Length != blurIterations)
            {
                mBlurPyramid = new int[blurIterations];
                for (int i = 0; i < blurIterations; i++)
                {
                    mBlurPyramid[i] = PyramidID(i);
                }
            }
            
            // blur downsample
            // ---------------
            int width = screenWidth;
            int height = screenHeight;
            for (int i = 0; i < blurIterations; i++)
            {
                // allocate temporary RT
                // ---------------------
                width /= 2;
                height /= 2;
                mDescriptor.width = width;
                mDescriptor.height = height;
                cmd.GetTemporaryRT(mBlurPyramid[i], mDescriptor);

                if (i == 0)
                {
                    cmd.Blit(mSourceRT.nameID, mBlurPyramid[0], mPassMaterial, 0);
                }
                else
                {
                    cmd.Blit(mBlurPyramid[i - 1], mBlurPyramid[i], mPassMaterial, 1);
                }
            }
            
            // blur upsample
            // -------------
            for (int i = blurIterations - 1; i > 2; i--)
            {
                float factor = 1;
                if (i == blurIterations - 1)
                {
                    factor = blurAmount - blurIterations;
                }
                mPassMaterial.SetFloat(_UpsampleFactor, factor * 0.7f);
                cmd.Blit(mBlurPyramid[i], mBlurPyramid[i - 1], mPassMaterial, 2);
            }
            
            // smearing
            // --------
            bool enableSmear = mVolumeComponent.m_SmearIntensity.value > 0;
            if (enableSmear)
            {
                int smearWidth = Mathf.Min(640, Mathf.RoundToInt(screenWidth * 0.5f));
                int smearHeight = Mathf.Min(480, Mathf.RoundToInt(screenHeight * 0.5f));
                mDescriptor.width = smearWidth;
                mDescriptor.height = smearHeight;
                cmd.GetTemporaryRT(_SmearTexture0, mDescriptor);
                cmd.GetTemporaryRT(_SmearTexture1, mDescriptor);
                mPassMaterial.SetVector(_SmearTextureSize, new Vector4(1f / smearWidth, 1f / smearHeight, smearWidth, smearHeight));
                mPassMaterial.SetVector(_SmearOffsetAttenuation, new Vector4(1, 0.3f));
                cmd.Blit(mBlurPyramid[1], _SmearTexture0, mPassMaterial, 3);
                mPassMaterial.SetVector(_SmearOffsetAttenuation, new Vector4(5, 1.2f));
                cmd.Blit(_SmearTexture0, _SmearTexture1, mPassMaterial, 3);
            }
            
            // composite
            // ---------
            cmd.SetGlobalTexture(_SlightBlurredTexture, mBlurPyramid[1]);
            cmd.SetGlobalTexture(_BlurredTexture, mBlurPyramid[2]);
            cmd.SetGlobalTexture(_SmearTexture, _SmearTexture1);
            cmd.Blit(mBlurPyramid[0], mSourceRT.nameID, mPassMaterial, 4);
        }
        
        context.ExecuteCommandBuffer(cmd);
        cmd.Clear();
        CommandBufferPool.Release(cmd);
    }
    
    public void Dispose()
    {
        CoreUtils.Destroy(mPassMaterial);
    }

    private int PyramidID(int i) => Shader.PropertyToID("_RetroBlurTexture" + i);
    
    // basic variables
    // ---------------
    private ProfilingSampler    mProfilingSampler;
    private Retro mVolumeComponent;
    private Material            mPassMaterial;
    // render pass related
    // -------------------
    private RTHandle mSourceRT;
    private RenderTextureDescriptor mDescriptor;
    // constants
    // ---------
    private int[] mBlurPyramid;
    
    private readonly int _SmearTexture0 = Shader.PropertyToID("_SmearTexture0");
    private readonly int _SmearTexture1 = Shader.PropertyToID("_SmearTexture1");
    
    private static readonly int _BlurBias = Shader.PropertyToID("_BlurBias");
    private static readonly int _UpsampleFactor = Shader.PropertyToID("_UpsampleFactor");
    private static readonly int _SmearTextureSize = Shader.PropertyToID("_SmearTextureSize");
    private static readonly int _SmearOffsetAttenuation = Shader.PropertyToID("_SmearOffsetAttenuation");
    private static readonly int _BleedIntensity = Shader.PropertyToID("_BleedIntensity");
    private static readonly int _SmearIntensity = Shader.PropertyToID("_SmearIntensity");
    private static readonly int _EdgeIntensity = Shader.PropertyToID("_EdgeIntensity");
    private static readonly int _EdgeDistance = Shader.PropertyToID("_EdgeDistance");
    private static readonly int _SlightBlurredTexture = Shader.PropertyToID("_SlightBlurredTexture");
    private static readonly int _BlurredTexture = Shader.PropertyToID("_BlurredTexture");
    private static readonly int _SmearTexture = Shader.PropertyToID("_SmearTexture");
}
