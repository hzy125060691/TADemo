using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
//[ExecuteAlways]
public class RotateByTime : MonoBehaviour
{
    public Vector3 RotateAxis = Vector3.up;
    public Single RotateSpeed = -100f;
    void Update()
    {
        transform.localRotation = transform.localRotation * Quaternion.AngleAxis(RotateSpeed * Time.deltaTime, RotateAxis);
    }
}
