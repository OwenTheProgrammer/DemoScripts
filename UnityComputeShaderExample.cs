//I dont know if this script works but it should get the point
//across if it doesnt for some reason
using UnityEngine;

public class ExampleBlockGroup : MonoBehaviour {
    
    //Compute shader things
    private ComputeShader Shader;
    private ComputeBuffer Memory; //Consider using GraphicsBuffer when you can
    private (int x, int y, int z) Dims;
    private int Kernel;

    //this is your data array
    private float[] Array;

    //this should be its own function but for simplicity
    //its also in the Setup.
    private void InitShaderMem() {
        if(Memory != null && Memory.IsValid()) Memory.Release();
        Memory = new ComputeBuffer(Array.Length, sizeof(float));
    }

    private void SetupComputeShaders() {
        Kernel = Shader.FindKernel("KERNEL_NAME_HERE"); //you can also use a number index but whatever
        Array = new float[10000]; // using 10k floats as an example

        //if there is memory allocated for some reason, re-init
        if(Memory != null && Memory.IsValid()) Memory.Release();
        //Setup GPU side memory buffer
        Memory = new ComputeBuffer(Array.Length, sizeof(float));
        
        //This is when you would fill "Array" with the values you want to use
        //-----------

        Memory.SetData(Array);

        //Set all Uniforms for the shader
        //example:
        Shader.SetBuffer(Kernel, "BUFFER_NAME", Memory);

        //This is my way of computing the block size automatically
        //this is effectively the same as [numthreads(10000,1,1)]
        //but you dont have to worry about block calculation
        Dims = GetWarpDims(Shader, Kernel, new Vector3Int(Array.Length, 0, 0));

        //Dispatch the compute shader
        Shader.Dispatch(Kernel, Dims.x, Dims.y, Dims.z);

        //Get the data from the compute shader
        //for this example lets just over-write the values from the input array
        Memory.GetData(Array);

        //dont forget to Dispose the memory you allocated :)
        //or keep going suit yourself! you can also index into the
        //memory buffer by changing specific values so you dont have
        //to change the whole array if you are looking to change an item.
        DisposeForTheLoveOfGod();
    }

    private (int,int,int) GetWarpDims(ComputeShader shader, int kernel, Vector3Int Dims) {
        uint TSX, TSY, TSZ;
        //https://docs.unity3d.com/ScriptReference/ComputeShader.GetKernelThreadGroupSizes.html
        //this returns the [numthreads(x,y,z)] values!
        shader.GetKernelThreadGroupSizes(kernel, out TSX, out TSY, out TSZ);
        int GROUPX = Mathf.CeilToInt(Dims.x / TSX);
        int GROUPY = Mathf.CeilToInt(Dims.y / TSY);
        int GROUPZ = Mathf.CeilToInt(Dims.z / TSZ);
        if(GROUPX == 0) GROUPX = 1;
        if(GROUPY == 0) GROUPY = 1;
        if(GROUPZ == 0) GROUPZ = 1;
        return (GROUPX,GROUPY,GROUPZ);
    }

    private void DisposeForTheLoveOfGod() {
        if(Memory != null && Memory.IsValid()) Memory.Release();
        Memory = null;
    }

    //please remember to dispose of your memory when you are done
    //this is the reason why C# has garbage collection
    //because of thooose programmers... you know who you are.
    private void OnDisable() => DisposeForTheLoveOfGod();
    private void OnDestory() => DisposeForTheLoveOfGod();
}