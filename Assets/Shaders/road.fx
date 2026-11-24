float4x4 gWorldViewProjection : WORLDVIEWPROJECTION;

texture gRoad;
texture gGravel;
texture gSand;
texture gGrass;

static const float BLEND_TILE = 8.0;
float gGravelRepeat;

sampler2D sRoad = sampler_state
{
	Texture = gRoad;
	AddressU = Wrap;
	AddressV = Wrap;
	MinFilter = Linear;
	MagFilter = Linear;
	MipFilter = Linear;
};

sampler2D sGravel = sampler_state
{
	Texture = gGravel;
	AddressU = Wrap;
	AddressV = Wrap;
	MinFilter = Linear;
	MagFilter = Linear;
	MipFilter = Linear;
};

sampler2D sSand = sampler_state
{
	Texture = gSand;
	AddressU = Wrap;
	AddressV = Wrap;
	MinFilter = Linear;
	MagFilter = Linear;
	MipFilter = Linear;
};

sampler2D sGrass = sampler_state
{
	Texture = gGrass;
	AddressU = Wrap;
	AddressV = Wrap;
	MinFilter = Linear;
	MagFilter = Linear;
	MipFilter = Linear;
};

struct VSInput
{
	float3 Pos : POSITION0;
	float4 Color : COLOR0;
	float2 UV : TEXCOORD0;
};

struct VSOutput
{
	float4 Pos : POSITION0;
	float4 Color : COLOR0;
	float2 UV : TEXCOORD0;
	float2 World : TEXCOORD1;
};

VSOutput VS(VSInput input)
{
	VSOutput o;
	o.Pos = mul(float4(input.Pos, 1.0), gWorldViewProjection);
	o.Color = input.Color;
	o.UV = input.UV;
	o.World = input.Pos.xy;
	return o;
}

float4 PS(VSOutput i) : COLOR0
{
	float t = saturate(i.UV.x - 1.0);
	float3 road = tex2D(sRoad, float2(min(i.UV.x, 0.999), i.UV.y)).rgb;
	float3 gravel = tex2D(sGravel, float2(min(i.UV.x, 0.999), i.UV.y * gGravelRepeat)).rgb;
	road = lerp(road, gravel, i.Color.r * (1.0 - saturate(t * 2.0)));
	float3 sand = tex2D(sSand, i.World / BLEND_TILE).rgb;
	float3 grass = tex2D(sGrass, i.World / BLEND_TILE).rgb;
	float3 col = lerp(road, sand, saturate(t * 2.0));
	col = lerp(col, grass, saturate(t * 2.0 - 1.0));
	return float4(col * i.Color.a, 1.0);
}

technique road
{
	pass P0
	{
		VertexShader = compile vs_2_0 VS();
		PixelShader = compile ps_2_0 PS();
	}
}
