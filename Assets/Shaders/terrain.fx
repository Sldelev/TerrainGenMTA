float4x4 gWorldViewProjection : WORLDVIEWPROJECTION;

texture gGrass;
texture gRock;
texture gSand;
texture gSnow;

static const float TILE = 8.0;

sampler2D sGrass = sampler_state
{
	Texture = gGrass;
	AddressU = Wrap;
	AddressV = Wrap;
};

sampler2D sRock = sampler_state
{
	Texture = gRock;
	AddressU = Wrap;
	AddressV = Wrap;
};

sampler2D sSand = sampler_state
{
	Texture = gSand;
	AddressU = Wrap;
	AddressV = Wrap;
};

sampler2D sSnow = sampler_state
{
	Texture = gSnow;
	AddressU = Wrap;
	AddressV = Wrap;
};

struct VSInput
{
	float3 Pos : POSITION0;
	float4 Weights : COLOR0;
};

struct VSOutput
{
	float4 Pos : POSITION0;
	float4 Weights : COLOR0;
	float Shade : TEXCOORD0;
	float2 World : TEXCOORD1;
};

VSOutput VS(VSInput input)
{
	VSOutput o;
	o.Pos = mul(float4(input.Pos, 1.0), gWorldViewProjection);
	o.Weights = input.Weights;
	o.Shade = input.Weights.a;
	o.World = input.Pos.xy;
	return o;
}

float4 PS(VSOutput i) : COLOR0
{
	float2 uv = i.World / TILE;
	float3 grass = tex2D(sGrass, uv).rgb;
	float3 rock = tex2D(sRock, uv).rgb;
	float3 sand = tex2D(sSand, uv).rgb;
	float3 snow = tex2D(sSnow, uv).rgb;

	float stoneW = i.Weights.r;
	float snowW = i.Weights.g;
	float sandW = i.Weights.b;
	float grassW = saturate(1.0 - stoneW - snowW - sandW);

	float3 col = grass * grassW + rock * stoneW + snow * snowW + sand * sandW;
	return float4(col * i.Shade, 1.0);
}

technique terrain
{
	pass P0
	{
		VertexShader = compile vs_2_0 VS();
		PixelShader = compile ps_2_0 PS();
	}
}
