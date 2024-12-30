using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class Retro : VolumeComponent, IPostProcessComponent
{
    [Space]
    public BoolParameter m_Enable = new(false);
    [Space]
    public ClampedFloatParameter m_BleedRadius       = new(0, 0, 1);
    public ClampedFloatParameter m_BleedDirection    = new(0, -1, 1);
    public ClampedFloatParameter m_BleedIntensity    = new(0, 0, 2);
    [Space]
    public ClampedFloatParameter m_SmearIntensity    = new(0, 0, 1);
    [Space]
    public ClampedFloatParameter m_EdgeIntensity     = new(0, 0, 2);
    public ClampedFloatParameter m_EdgeDistance      = new(0, 0, 0.005f);
    [Space]
    public ClampedFloatParameter m_TapeNoiseAmount   = new(0.0f, 0.0f, 0.999f);
    public ClampedFloatParameter m_TapeNoiseSpeed    = new(0.0f, 0.0f, 1.0f);
    public ClampedFloatParameter m_TapeNoiseAlpha    = new(0.0f, 0.0f, 1.0f);
    [Space]
    public ClampedFloatParameter m_InterlacingAmount = new(0.0f, 0.0f, 10.0f);
    [Space] 
    public ClampedFloatParameter m_ScanlineSpeed     = new(0.0f, 0.0f, 0.5f);
    public ClampedFloatParameter m_ScanlineFrequency = new(20.0f, 20.0f, 70.0f);
    public ClampedFloatParameter m_ScanlineIntensity = new(0.0f, 0.0f, 1.0f);

    public bool IsActive() => m_Enable.value;
    public bool IsTileCompatible() => false;
}
