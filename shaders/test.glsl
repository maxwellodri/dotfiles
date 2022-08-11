//--- hatsuyuki ---
// by Catzpaw 2016
#version 450
#define speed 1.
uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;
out vec4 out_color;

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 1.0 / 2.0, 1.0 / 1.0, 2.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 5.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
void main(void){
    vec2 uv = -1.0 + 2.0*gl_FragCoord.xy / resolution.xy;
    uv.x *=  resolution.x / resolution.y;
    vec2 ms = (mouse.xy / resolution.xy);
    vec2 position = ( gl_FragCoord.xy / resolution.xy );
    //vec3 rgb = hsv2rgb(vec3(time / .01 + (1000.0 - position.x) + position.y, 1, 1));
    vec3 rgb = hsv2rgb(vec3(time * speed + (1.0 - position.x) + position.y, 1, 0.8));
    vec4 rgba = vec4(rgb.xyz, 2555555);
    // background
    vec3 color = vec3(0.9 + 0.2*uv.y);

    // bubbles
    for( int i=0; i<35; i++ )
    {
        // bubble seeds
        float pha =      sin(float(i)*546.13+1.0)*0.5 + 0.5;
        float siz = pow( sin(float(i)*651.74+5.0)*0.5 + 0.5, 4.0 );
        float pox =      sin(float(i)*321.55+4.2) * resolution.x / resolution.y;

        // buble size, position and color
        float rad = 0.2 + 0.5*siz;
        vec2  pos = vec2( pox, -1.0-rad + (2.0+2.0*rad)*mod(pha+0.1*time*(0.1+0.1*siz),1.0));
        float distToMs = length(pos - ms);
        pos *= length(pos - (ms * 1.5-0.5));
        float dis = length( uv - pos );


        vec3  col = mix( vec3(rgba), vec3(0.1,0.4,0.8), 0.5+0.5*sin(float(i)*1.2+1.9));
        //    col+= 8.0*smoothstep( rad*0.95, rad, dis );

        // render
        float f = length(uv-pos)/rad;
        f = sqrt(clamp(1.0-f*f,0.0,1.0));
        color -= col.zyx *(1.0-smoothstep( rad*0.95, rad, dis )) * f;
    }

    // vigneting
    color *= sqrt(1.5-0.5*length(uv));

  out_color =  vec4(color,1.0);
}
