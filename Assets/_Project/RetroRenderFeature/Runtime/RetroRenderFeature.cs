using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[Serializable]
public class RetroSettings
{
    public RenderPassEvent m_RenderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    public Shader m_RetroShader;
}

public class RetroRenderFeature : ScriptableRendererFeature
{
    [SerializeField]
    private RetroSettings m_Settings = new ();
    private RetroRenderPass mPass;
    
    public override void Create()
    {
        if (m_Settings.m_RetroShader == null) return;
        mPass = new RetroRenderPass(name, m_Settings);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (m_Settings.m_RetroShader == null) return;
        Retro volumeComponent = VolumeManager.instance.stack.GetComponent<Retro>();
        if (!volumeComponent || !volumeComponent.IsActive()) return;
        if (renderingData.cameraData.cameraType != CameraType.Game) return;
        
        mPass.Setup(volumeComponent);
        renderer.EnqueuePass(mPass);
    }

    protected override void Dispose(bool disposing)
    {
        mPass.Dispose();
    }
}
