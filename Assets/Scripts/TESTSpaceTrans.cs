using System;
using System.Collections;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

public class TESTSpaceTrans : MonoBehaviour
{
    public Camera Cam;
    public Vector2 UV = new Vector2();
    void Awake()
    {
        Cam = GetComponent<Camera>();
    }

    private void OnDrawGizmos()
    {
        if (!Cam)
        {
            return;
        }
        Gizmos.color = Color.red;
        var mouseOverWindow = UnityEditor.EditorWindow.mouseOverWindow;
        System.Reflection.Assembly assembly = typeof(UnityEditor.EditorWindow).Assembly;
        System.Type type = assembly.GetType("UnityEditor.PlayModeView");

        Vector2 size = (Vector2) type.GetMethod(
                "GetMainPlayModeViewTargetSize",
                System.Reflection.BindingFlags.NonPublic |
                System.Reflection.BindingFlags.Static
            ).Invoke(mouseOverWindow, null);
           
         
        var pos = Cam.ScreenToWorldPoint(new Vector3(UV.x * size.x, UV.y *size.y
            , Cam.farClipPlane));
        Gizmos.DrawLine(Cam.transform.position, pos);
        var vp = Cam.projectionMatrix * Cam.worldToCameraMatrix;
        var uv = (UV - new Vector2(0.5f, 0.5f)) * 2;
        var uv1 = new Vector4(uv.x, uv.y, 1, 1);
        var uv2 = new Vector4(uv.x, uv.y, -1, 1);
        var pOffset = uv1 ;
        var pView = vp.inverse * pOffset;
        pView /= pView.w;

        var pOffset2 = uv2;
        var pView2 = vp.inverse * pOffset2;
        pView2 /= pView2.w;
     

        Gizmos.color = Color.cyan;
        //Gizmos.DrawLine(Cam.transform.position, pView);
        Gizmos.DrawLine(pView2, pView);


    }
}
