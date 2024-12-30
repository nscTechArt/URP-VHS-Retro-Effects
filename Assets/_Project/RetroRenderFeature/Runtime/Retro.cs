using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class Retro : VolumeComponent, IPostProcessComponent
{
    [Space]
    public BoolParameter m_Enable = new(false);

    public ClampedFloatParameter m_BleedRadius = new(0, 0, 1);
    public ClampedFloatParameter m_BleedDirection = new(0, -1, 1);
    public ClampedFloatParameter m_BleedIntensity = new(0, 0, 2);
    
    public ClampedFloatParameter m_SmearIntensity = new(0, 0, 1);

    public ClampedFloatParameter m_EdgeIntensity = new(0, 0, 2);
    public ClampedFloatParameter m_EdgeDistance = new(0, 0, 0.005f);

    public bool IsActive() => m_Enable.value;
    public bool IsTileCompatible() => false;
}
