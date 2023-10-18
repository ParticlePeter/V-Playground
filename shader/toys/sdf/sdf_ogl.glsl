// --- VERT ---
#version 330
// UBO Camera Matrices and time
layout( std140 ) uniform uboViewer  {
	mat4	WVPM;		// Combined World View Projection Matrix
	mat4	VIEW;		// View Matrix, Transforms World Space Positions into Camera View Space
	mat4	PROJ;		// Projection Matrix, Transforms Camera View Space into NDC Space
	mat4	ORTH;		// Orthografik Projection, Transforms Window Coordinates into NDC Space
	mat4	IWVP;		// Inverse World View Projection Matrix
	vec3	camWorld;	// Camera Position in World Space
	float	fovy;		// Field of View in Y

	float	time;		// timer started at program start
	float frame;		// time step of a frame
	float	beat;		// beat from Midi / OSC
	int	tick;		// tick from Midi / OSC

	vec2	drawArea;	// Draw Area is the Size of the Viewport in x and y
	vec2	invDArea;	// Inverse Draw Area
	float	aspect;		// Aspect Ration of Draw Area
	float	invAsp;		// Invesrse Aspect Ratio
	float	near;		// Near Clip Plane
	float	far;			// Far Clip Plane
};

// Input Uniforms
uniform vec4 Color;

// Input Attribs
layout( location = 0 )	in  vec2 inVertex;

// Raster Attribs
out vec2	vsTexST0;


// Main
void main( void )  {
	gl_Position = vec4( inVertex, 0, 1 );
	vsTexST0  = inVertex;
}


// --- FRAG ---
#version 330
// UBO Camera Matrices and time
layout( std140 ) uniform uboViewer  {
	mat4	WVPM;		// Combined World View Projection Matrix
	mat4	VIEW;		// View Matrix, Transforms World Space Positions into Camera View Space
	mat4	PROJ;		// Projection Matrix, Transforms Camera View Space into NDC Space
	mat4	ORTH;		// Orthografik Projection, Transforms Window Coordinates into NDC Space
	mat4	IWVP;		// Inverse World View Projection Matrix
	vec3	camWorld;	// Camera Position in World Space
	float	fovy;		// Field of View in Y

	float	time;		// timer started at program start
	float frame;		// time step of a frame
	float	beat;		// beat from Midi / OSC
	int	tick;		// tick from Midi / OSC

	vec2	drawArea;	// Draw Area is the Size of the Viewport in x and y
	vec2	invDArea;	// Inverse Draw Area
	float	aspect;		// Aspect Ration of Draw Area
	float	invAsp;		// Invesrse Aspect Ratio
	float	near;		// Near Clip Plane
	float	far;			// Far Clip Plane
};


// Input Uniforms
uniform vec4 Color;

// Input Attribs
in vec2	vsTexST0;
in vec4 gl_FragCoord;


// Output Fragments
out vec4 frag;


float sdBox( vec3 p, vec3 b )  {
	vec3 d = abs( p ) - b;
	return min( max( d.x, max( d.y, d.z )), 0.0 ) + length( max( d, 0.0 ));
}


float density( vec3 pos )  {
	return sdBox( pos, vec3( 2 ) );
}


void genRay( out vec3 pos, out vec3 dir )  {
	vec4 projPos = vec4( vsTexST0, -1, 1 );
	projPos = IWVP * projPos;
	pos = projPos.xyz / projPos.w;
	projPos = vec4( vsTexST0, 1, 1 );
	projPos = IWVP * projPos;
	dir = normalize( projPos.xyz / projPos.w - pos );
}

vec3 gradient( vec3 pos, float d )  {
	float e = 0.000001;
	float dx = density( pos + vec3( e, 0, 0 )) - d;
	float dy = density( pos + vec3( 0, e, 0 )) - d;
	float dz = density( pos + vec3( 0, 0, e )) - d;
	return normalize( vec3( dx, dy, dz )); // / 0.001;
}

/*
vec3 normal( in vec3 pos )  {
	vec3 eps = vec3( 0.001, 0.0, 0.0 );
	vec3 nor = vec3(
	    density(pos+eps.xyy).x - density(pos-eps.xyy).x,
	    density(pos+eps.yxy).x - density(pos-eps.yxy).x,
	    density(pos+eps.yyx).x - density(pos-eps.yyx).x );
	return normalize(nor);
}
*/

// Main
void main( void )  {
	vec3 pos; vec3 dir;
	genRay( pos, dir );

	float epsilon = 0.00001;
	float	sumD = 0.0;
	for( int i = 0; i < 500; ++i )  {
		float d = density( pos );
		sumD += d;
		if ( sumD > far ) break;
		if ( d <= epsilon * sumD )  {
			vec3  n = gradient( pos, d );
			float l = abs( dot( mat3( WVPM ) * vec3( 0, 0, 1 ), n ));	// Camera is Lightsource
			frag = vec4( l, l, l, 1 );
			return;
		}

		pos += dir * d;
	}

	frag = vec4( - dir, 1 );
}




/*
// Created by inigo quilez - iq/2013
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.

// A list of usefull distance function to simple primitives, and an example on how to 
// do some interesting boolean operations, repetition and displacement.
//
// More info here: http://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm

float sdPlane( vec3 p )
{
	return p.y;
}

float sdSphere( vec3 p, float s )
{
    return length(p)-s;
}

float sdBox( vec3 p, vec3 b )
{
  vec3 d = abs(p) - b;
  return min(max(d.x,max(d.y,d.z)),0.0) +
         length(max(d,0.0));
}

float udRoundBox( vec3 p, vec3 b, float r )
{
  return length(max(abs(p)-b,0.0))-r;
}

float sdTorus( vec3 p, vec2 t )
{
  vec2 q = vec2(length(p.xz)-t.x,p.y);
  return length(q)-t.y;
}

float sdHexPrism( vec3 p, vec2 h )
{
    vec3 q = abs(p);
    return max(q.z-h.y,max(q.x+q.y*0.57735,q.y*1.1547)-h.x);
}

float sdCapsule( vec3 p, vec3 a, vec3 b, float r )
{
	vec3 pa = p - a;
	vec3 ba = b - a;
	float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
	
	return length( pa - ba*h ) - r;
}

float sdTriPrism( vec3 p, vec2 h )
{
    vec3 q = abs(p);
    return max(q.z-h.y,max(q.x*0.866025+p.y*0.5,-p.y)-h.x*0.5);
}

float sdCylinder( vec3 p, vec2 h )
{
  return max( length(p.xz)-h.x, abs(p.y)-h.y );
}

float sdCone( in vec3 p, in vec3 c )
{
    vec2 q = vec2( length(p.xz), p.y );
	return max( max( dot(q,c.xy), p.y), -p.y-c.z );
}

float length2( vec2 p )
{
	return sqrt( p.x*p.x + p.y*p.y );
}

float length6( vec2 p )
{
	p = p*p*p; p = p*p;
	return pow( p.x + p.y, 1.0/6.0 );
}

float length8( vec2 p )
{
	p = p*p; p = p*p; p = p*p;
	return pow( p.x + p.y, 1.0/8.0 );
}

float sdTorus82( vec3 p, vec2 t )
{
  vec2 q = vec2(length2(p.xz)-t.x,p.y);
  return length8(q)-t.y;
}

float sdTorus88( vec3 p, vec2 t )
{
  vec2 q = vec2(length8(p.xz)-t.x,p.y);
  return length8(q)-t.y;
}

float sdCylinder6( vec3 p, vec2 h )
{
  return max( length6(p.xz)-h.x, abs(p.y)-h.y );
}

//----------------------------------------------------------------------

float opS( float d1, float d2 )
{
    return max(-d2,d1);
}

vec2 opU( vec2 d1, vec2 d2 )
{
	return (d1.x<d2.x) ? d1 : d2;
}

vec3 opRep( vec3 p, vec3 c )
{
    return mod(p,c)-0.5*c;
}

vec3 opTwist( vec3 p )
{
    float  c = cos(10.0*p.y+10.0);
    float  s = sin(10.0*p.y+10.0);
    mat2   m = mat2(c,-s,s,c);
    return vec3(m*p.xz,p.y);
}

//----------------------------------------------------------------------

vec2 density( in vec3 pos )
{
    vec2 res = opU( vec2( sdPlane(     pos), 1.0 ),
	                vec2( sdSphere(    pos-vec3( 0.0,0.25, 0.0), 0.25 ), 46.9 ) );
    res = opU( res, vec2( sdBox(       pos-vec3( 1.0,0.25, 0.0), vec3(0.25) ), 3.0 ) );
    res = opU( res, vec2( udRoundBox(  pos-vec3( 1.0,0.25, 1.0), vec3(0.15), 0.1 ), 41.0 ) );
	res = opU( res, vec2( sdTorus(     pos-vec3( 0.0,0.25, 1.0), vec2(0.20,0.05) ), 25.0 ) );
    res = opU( res, vec2( sdCapsule(   pos,vec3(-1.3,0.20,-0.1), vec3(-1.0,0.20,0.2), 0.1  ), 31.9 ) );
	res = opU( res, vec2( sdTriPrism(  pos-vec3(-1.0,0.25,-1.0), vec2(0.25,0.05) ),43.5 ) );
	res = opU( res, vec2( sdCylinder(  pos-vec3( 1.0,0.30,-1.0), vec2(0.1,0.2) ), 8.0 ) );
	res = opU( res, vec2( sdCone(      pos-vec3( 0.0,0.50,-1.0), vec3(0.8,0.6,0.3) ), 55.0 ) );
	res = opU( res, vec2( sdTorus82(   pos-vec3( 0.0,0.25, 2.0), vec2(0.20,0.05) ),50.0 ) );
	res = opU( res, vec2( sdTorus88(   pos-vec3(-1.0,0.25, 2.0), vec2(0.20,0.05) ),43.0 ) );
	res = opU( res, vec2( sdCylinder6( pos-vec3( 1.0,0.30, 2.0), vec2(0.1,0.2) ), 12.0 ) );
	res = opU( res, vec2( sdHexPrism(  pos-vec3(-1.0,0.20, 1.0), vec2(0.25,0.05) ),17.0 ) );

#if 1
    res = opU( res, vec2( opS(
		             udRoundBox(  pos-vec3(-2.0,0.2, 1.0), vec3(0.15),0.05),
	                 sdSphere(    pos-vec3(-2.0,0.2, 1.0), 0.25)), 13.0 ) );
    res = opU( res, vec2( opS(
		             sdTorus82(  pos-vec3(-2.0,0.2, 0.0), vec2(0.20,0.1)),
	                 sdCylinder(  opRep( vec3(atan(pos.x+2.0,pos.z)/6.2831 + 0.1*iGlobalTime,
											  pos.y,
											  0.02+0.5*length(pos-vec3(-2.0,0.2, 0.0))),
									     vec3(0.05,1.0,0.05)), vec2(0.02,0.6))), 51.0 ) );
	res = opU( res, vec2( sdSphere(    pos-vec3(-2.0,0.25,-1.0), 0.2 ) + 
					                   0.03*sin(50.0*pos.x)*sin(50.0*pos.y+8.0*iGlobalTime)*sin(50.0*pos.z), 
                                       65.0 ) );

	res = opU( res, vec2( 0.5*sdTorus( opTwist(pos-vec3(-2.0,0.25, 2.0)),vec2(0.20,0.05)), 46.7 ) );
#endif

    return res;
}




vec2 castRay( in vec3 ro, in vec3 rd, in float maxd )
{
	float precis = 0.001;
    float h=precis*2.0;
    float t = 0.0;
    float m = -1.0;
    for( int i=0; i<60; i++ )
    {
        if( abs(h)<precis||t>maxd ) continue;//break;
        t += h;
	    vec2 res = density( ro+rd*t );
        h = res.x;
	    m = res.y;
    }

    if( t>maxd ) m=-1.0;
    return vec2( t, m );
}


float softshadow( in vec3 ro, in vec3 rd, in float mint, in float maxt, in float k )
{
	float res = 1.0;
    float t = mint;
    for( int i=0; i<30; i++ )
    {
		if( t<maxt )
		{
        float h = density( ro + rd*t ).x;
        res = min( res, k*h/t );
        t += 0.02;
		}
    }
    return clamp( res, 0.0, 1.0 );

}

vec3 calcNormal( in vec3 pos )
{
	vec3 eps = vec3( 0.001, 0.0, 0.0 );
	vec3 nor = vec3(
	    density(pos+eps.xyy).x - density(pos-eps.xyy).x,
	    density(pos+eps.yxy).x - density(pos-eps.yxy).x,
	    density(pos+eps.yyx).x - density(pos-eps.yyx).x );
	return normalize(nor);
}

float calcAO( in vec3 pos, in vec3 nor )
{
	float totao = 0.0;
    float sca = 1.0;
    for( int aoi=0; aoi<5; aoi++ )
    {
        float hr = 0.01 + 0.05*float(aoi);
        vec3 aopos =  nor * hr + pos;
        float dd = density( aopos ).x;
        totao += -(dd-hr)*sca;
        sca *= 0.75;
    }
    return clamp( 1.0 - 4.0*totao, 0.0, 1.0 );
}




vec3 render( in vec3 ro, in vec3 rd )
{ 
    vec3 col = vec3(0.0);
    vec2 res = castRay(ro,rd,20.0);
    float t = res.x;
	float m = res.y;
    if( m>-0.5 )
    {
        vec3 pos = ro + t*rd;
        vec3 nor = calcNormal( pos );

		//col = vec3(0.6) + 0.4*sin( vec3(0.05,0.08,0.10)*(m-1.0) );
		col = vec3(0.6) + 0.4*sin( vec3(0.05,0.08,0.10)*(m-1.0) );
		
        float ao = calcAO( pos, nor );

		vec3 lig = normalize( vec3(-0.6, 0.7, -0.5) );
		float amb = clamp( 0.5+0.5*nor.y, 0.0, 1.0 );
        float dif = clamp( dot( nor, lig ), 0.0, 1.0 );
        float bac = clamp( dot( nor, normalize(vec3(-lig.x,0.0,-lig.z))), 0.0, 1.0 )*clamp( 1.0-pos.y,0.0,1.0);

		float sh = 1.0;
		if( dif>0.02 ) { sh = softshadow( pos, lig, 0.02, 10.0, 7.0 ); dif *= sh; }

		vec3 brdf = vec3(0.0);
		brdf += 0.20*amb*vec3(0.10,0.11,0.13)*ao;
        brdf += 0.20*bac*vec3(0.15,0.15,0.15)*ao;
        brdf += 1.20*dif*vec3(1.00,0.90,0.70);

		float pp = clamp( dot( reflect(rd,nor), lig ), 0.0, 1.0 );
		float spe = sh*pow(pp,16.0);
		float fre = ao*pow( clamp(1.0+dot(nor,rd),0.0,1.0), 2.0 );

		col = col*brdf + vec3(1.0)*col*spe + 0.2*fre*(0.5+0.5*col);
		
	}

	col *= exp( -0.01*t*t );


	return vec3( clamp(col,0.0,1.0) );
}

void main( void )
{
	vec2 q = gl_FragCoord.xy/iResolution.xy;
    vec2 p = -1.0+2.0*q;
	p.x *= iResolution.x/iResolution.y;
    vec2 mo = iMouse.xy/iResolution.xy;
		 
	float time = 15.0 + iGlobalTime;

	// camera	
	vec3 ro = vec3( -0.5+3.2*cos(0.1*time + 6.0*mo.x), 1.0 + 2.0*mo.y, 0.5 + 3.2*sin(0.1*time + 6.0*mo.x) );
	vec3 ta = vec3( -0.5, -0.4, 0.5 );
	
	// camera tx
	vec3 cw = normalize( ta-ro );
	vec3 cp = vec3( 0.0, 1.0, 0.0 );
	vec3 cu = normalize( cross(cw,cp) );
	vec3 cv = normalize( cross(cu,cw) );
	vec3 rd = normalize( p.x*cu + p.y*cv + 2.5*cw );

	
    vec3 col = render( ro, rd );

	col = sqrt( col );

    gl_FragColor=vec4( col, 1.0 );
}

*/