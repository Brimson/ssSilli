/*
    Taken from [https://github.com/haasn/libplacebo/blob/master/src/shaders/sampling.c] [GPL 2.1]
    How bicubic scaling with only 4 texel fetches is done: [http://www.mate.tue.nl/mate/pdfs/10318.pdf]
    'Efficient GPU-Based Texture Interpolation using Uniform B-Splines'
*/

#include "ReShade.fxh"

uniform int kLod <
    ui_type = "drag";
    ui_label = "Level of Detail";
    ui_min = 0;
> = 0;

texture2D r_source : COLOR;
sampler2D s_source { Texture = r_source; };

// Hardcoded resolution because the filter works on power of 2.
texture2D r_dscale { Width = 1024; Height = 1024; MipLevels = 11; };
sampler2D s_dscale
{
    Texture = r_dscale;
    #if BUFFER_COLOR_BIT_DEPTH != 10
        SRGBTexture = true;
    #endif
};

struct v2f { float4 vpos : SV_POSITION; float2 uv : TEXCOORD0; };

// Empty shader to generate mipmaps.
void ps_mipgen(v2f input, out float4 c : SV_Target0) { c = tex2D(s_source, input.uv).rgb; }

float4 calcweights(float s)
{
    const float4 w1 = float4(-0.5, 0.1666, 0.3333, -0.3333);
    const float4 w2 = float4( 1.0, 0.0, -0.5, 0.5);
    const float4 w3 = float4(-0.6666, 0.0, 0.8333, 0.1666);
    float4 t = mad(w1, s, w2);
    t = mad(t, s, w2.yyzw);
    t = mad(t, s, w3);
    t.xy = mad(t.xy, rcp(t.zw), 1.0);
    t.x += s;
    t.y -= s;
    return t;
}

// Could calculate float3s for a bit more performance
void ps_cubic(v2f input, out float3 c : SV_Target0)
{
    float2 texsize = tex2Dsize(s_dscale, kLod);
    float2 pt = 1.0 / texsize;
    float2 fcoord = frac(input.uv * texsize + 0.5);
    float4 parmx = calcweights(fcoord.x);
    float4 parmy = calcweights(fcoord.y);
    float4 cdelta;
    cdelta.xz = parmx.rg * float2(-pt.x, pt.x);
    cdelta.yw = parmy.rg * float2(-pt.y, pt.y);
    // first y-interpolation
    float3 ar = tex2Dlod(s_dscale, float4(input.uv + cdelta.xy, 0.0, kLod)).rgb;
    float3 ag = tex2Dlod(s_dscale, float4(input.uv + cdelta.xw, 0.0, kLod)).rgb;
    float3 ab = lerp(ag, ar, parmy.b);
    // second y-interpolation
    float3 br = tex2Dlod(s_dscale, float4(input.uv + cdelta.zy, 0.0, kLod)).rgb;
    float3 bg = tex2Dlod(s_dscale, float4(input.uv + cdelta.zw, 0.0, kLod)).rgb;
    float3 aa = lerp(bg, br, parmy.b);
    // x-interpolation
    c = lerp(aa, ab, parmx.b);
}

technique Cubic
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = ps_mipgen;
        RenderTarget = r_dscale;
    }

    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = ps_cubic;
        #if BUFFER_COLOR_BIT_DEPTH != 10
            SRGBWriteEnable = true;
        #endif
    }
}
